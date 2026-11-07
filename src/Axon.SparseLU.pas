unit Axon.SparseLU;

(* Sparse LU factorisation, written here so that Axon needs no SuiteSparse
   library (reference, "Sparse operands").

   P A Q = L U, where
   - Q is a fill-reducing column order: minimum degree on the pattern of
     A + A' (the diagonal is ignored).
   - The factorisation is left-looking (Gilbert and Peierls, as in CSparse's
     cs_lu and in KLU): column k of L and U comes from solving L x = A(:, Q[k])
     with a sparse triangular solve that visits only the nonzero pattern of
     x, found by a depth-first search over the graph of L.
   - Rows are chosen by partial pivoting with a preference for the diagonal:
     the diagonal row is kept when its magnitude is at least PivotTol times
     the largest candidate, which preserves the symmetric ordering.
   - L is unit lower triangular with its diagonal stored first in each
     column; U is upper triangular with its diagonal stored last.

   Values are complex; a real matrix simply has zero imaginary parts. *)

interface

uses
  System.SysUtils,
  Axon.Complex, Axon.Values;

type
  TSparseLU = class
  public
    N: Integer;
    Lp, Li: TArray<Integer>;     // L by columns; row indices in pivot order
    Lx: TArray<TComplex>;
    Up, Ui: TArray<Integer>;     // U by columns; row indices in pivot order
    Ux: TArray<TComplex>;
    Pinv: TArray<Integer>;       // row i of A is row Pinv[i] of L U
    Q: TArray<Integer>;          // column k of L U is column Q[k] of A
    { B := A \ B for one right-hand side of length N. }
    procedure Solve(var B: TArray<TComplex>);
  end;

{ A fill-reducing order of the columns of a square sparse matrix. }
function MinimumDegreeOrder(S: TSparseObj): TArray<Integer>;

{ Factorises a square sparse matrix. Raises SingularMatrix when it is
  singular, or singular to working precision. The caller frees the result. }
function SparseFactor(S: TSparseObj): TSparseLU;

implementation

uses
  System.Generics.Collections, System.Math,
  Axon.Errors;

const
  PivotTol = 0.1;
  MachineEps = 2.220446049250313e-16;

{ ---------------- ordering ---------------- }

function MinimumDegreeOrder(S: TSparseObj): TArray<Integer>;
var
  N, I, J, P, K, A, B, Best, MinDeg, Stamp: Integer;
  Adj: array of TList<Integer>;
  Mark, Deg, Head, Next, Prev: TArray<Integer>;
  Nbrs: TArray<Integer>;

  // Nodes are kept in one doubly-linked list per degree, so the node of
  // least degree is found without scanning every node.
  procedure Link(V: Integer);
  begin
    Deg[V] := Adj[V].Count;
    Prev[V] := -1;
    Next[V] := Head[Deg[V]];
    if Next[V] >= 0 then
      Prev[Next[V]] := V;
    Head[Deg[V]] := V;
    if Deg[V] < MinDeg then
      MinDeg := Deg[V];
  end;

  procedure Unlink(V: Integer);
  begin
    if Prev[V] >= 0 then
      Next[Prev[V]] := Next[V]
    else
      Head[Deg[V]] := Next[V];
    if Next[V] >= 0 then
      Prev[Next[V]] := Prev[V];
  end;

begin
  N := S.Cols;
  SetLength(Result, N);
  SetLength(Adj, N);
  SetLength(Mark, N);
  SetLength(Deg, N);
  SetLength(Head, N + 1);
  SetLength(Next, N);
  SetLength(Prev, N);
  for I := 0 to N - 1 do
  begin
    Adj[I] := TList<Integer>.Create;
    Mark[I] := -1;
  end;
  try
    // The pattern of A + A', without the diagonal and without duplicates.
    for J := 0 to N - 1 do
      for P := S.ColPtr[J] to S.ColPtr[J + 1] - 1 do
      begin
        I := S.RowIdx[P];
        if I <> J then
        begin
          Adj[I].Add(J);
          Adj[J].Add(I);
        end;
      end;
    for I := 0 to N - 1 do
    begin
      Nbrs := Adj[I].ToArray;
      Adj[I].Clear;
      for A in Nbrs do
        if Mark[A] <> I then
        begin
          Mark[A] := I;
          Adj[I].Add(A);
        end;
    end;
    for I := 0 to N - 1 do
      Mark[I] := -1;
    for I := 0 to N do
      Head[I] := -1;
    MinDeg := N;
    for I := N - 1 downto 0 do
      Link(I);
    Stamp := 0;

    for K := 0 to N - 1 do
    begin
      // An uneliminated node of least degree.
      while Head[MinDeg] < 0 do
        Inc(MinDeg);
      Best := Head[MinDeg];
      Unlink(Best);
      Result[K] := Best;
      // Eliminating Best joins its neighbours into a clique.
      Nbrs := Adj[Best].ToArray;
      for A in Nbrs do
      begin
        Unlink(A);
        Adj[A].Remove(Best);
        // A fresh stamp per neighbour marks its current adjacency.
        Inc(Stamp);
        Mark[A] := Stamp;           // A itself is not its own neighbour
        for B in Adj[A] do
          Mark[B] := Stamp;
        for B in Nbrs do
          if Mark[B] <> Stamp then
          begin
            Mark[B] := Stamp;
            Adj[A].Add(B);
          end;
      end;
      for A in Nbrs do
        Link(A);
      Adj[Best].Clear;
    end;
  finally
    for I := 0 to N - 1 do
      Adj[I].Free;
  end;
end;

{ ---------------- factorisation ---------------- }

function SparseFactor(S: TSparseObj): TSparseLU;
var
  N, K, Col, Top, P, I, J, Jn, Ipiv, LNz, UNz: Integer;
  X: TArray<TComplex>;
  Xi, Stack, PStack: TArray<Integer>;
  Marked: TArray<Boolean>;
  A, T, MaxPivot, MinPivot: Double;
  Pivot: TComplex;
  F: TSparseLU;

  procedure GrowL;
  begin
    if LNz >= Length(F.Li) then
    begin
      SetLength(F.Li, 2 * Length(F.Li) + N);
      SetLength(F.Lx, Length(F.Li));
    end;
  end;

  procedure GrowU;
  begin
    if UNz >= Length(F.Ui) then
    begin
      SetLength(F.Ui, 2 * Length(F.Ui) + N);
      SetLength(F.Ux, Length(F.Ui));
    end;
  end;

  { Depth-first search from row J over the graph of L built so far; pushes
    the nodes reached onto Xi[Top..N-1] in topological order. }
  procedure Dfs(J0: Integer);
  var
    Head, J, Jn, P, P2, I: Integer;
    Done: Boolean;
  begin
    // Locals of its own: the caller's loop counters must not change.
    Head := 0;
    Stack[0] := J0;
    while Head >= 0 do
    begin
      J := Stack[Head];
      Jn := F.Pinv[J];
      if not Marked[J] then
      begin
        Marked[J] := True;
        if Jn < 0 then PStack[Head] := 0 else PStack[Head] := F.Lp[Jn];
      end;
      Done := True;
      if Jn < 0 then P2 := 0 else P2 := F.Lp[Jn + 1];
      P := PStack[Head];
      while P < P2 do
      begin
        I := F.Li[P];
        if not Marked[I] then
        begin
          PStack[Head] := P;     // resume here when I is finished
          Inc(Head);
          Stack[Head] := I;
          Done := False;
          Break;
        end;
        Inc(P);
      end;
      if Done then
      begin
        Dec(Head);
        Dec(Top);
        Xi[Top] := J;
      end;
    end;
  end;

begin
  N := S.Cols;
  F := TSparseLU.Create;
  try
    F.N := N;
    F.Q := MinimumDegreeOrder(S);
    SetLength(F.Pinv, N);
    for I := 0 to N - 1 do
      F.Pinv[I] := -1;
    SetLength(F.Lp, N + 1);
    SetLength(F.Up, N + 1);
    SetLength(F.Li, 4 * S.Nnz + N);
    SetLength(F.Lx, Length(F.Li));
    SetLength(F.Ui, 4 * S.Nnz + N);
    SetLength(F.Ux, Length(F.Ui));
    SetLength(X, N);
    SetLength(Xi, N);
    SetLength(Stack, N);
    SetLength(PStack, N);
    SetLength(Marked, N);
    LNz := 0;
    UNz := 0;
    MaxPivot := 0;
    MinPivot := Infinity;

    for K := 0 to N - 1 do
    begin
      F.Lp[K] := LNz;   // L(:, k) starts here
      F.Up[K] := UNz;   // U(:, k) starts here
      Col := F.Q[K];

      // The nonzero pattern of x = L \ A(:, col): the nodes reachable from
      // the rows of A(:, col) in the graph of L.
      Top := N;
      for P := S.ColPtr[Col] to S.ColPtr[Col + 1] - 1 do
        if not Marked[S.RowIdx[P]] then
          Dfs(S.RowIdx[P]);
      for P := Top to N - 1 do
        Marked[Xi[P]] := False;

      // The sparse triangular solve, in topological order.
      for P := Top to N - 1 do
        X[Xi[P]] := Cx(0, 0);
      for P := S.ColPtr[Col] to S.ColPtr[Col + 1] - 1 do
        X[S.RowIdx[P]] := S.V[P];
      for P := Top to N - 1 do
      begin
        J := Xi[P];
        Jn := F.Pinv[J];
        if Jn < 0 then
          Continue;           // row J is not pivotal yet: no column of L
        // L is unit diagonal (stored first), so only the update remains.
        for I := F.Lp[Jn] + 1 to F.Lp[Jn + 1] - 1 do
          X[F.Li[I]] := CSub(X[F.Li[I]], CMul(F.Lx[I], X[J]));
      end;

      // Split x into U (pivotal rows) and pivot candidates.
      Ipiv := -1;
      A := -1;
      for P := Top to N - 1 do
      begin
        I := Xi[P];
        if F.Pinv[I] < 0 then
        begin
          T := CAbs(X[I]);
          if T > A then
          begin
            A := T;
            Ipiv := I;
          end;
        end
        else
        begin
          GrowU;
          F.Ui[UNz] := F.Pinv[I];
          F.Ux[UNz] := X[I];
          Inc(UNz);
        end;
      end;
      if (Ipiv < 0) or (A <= 0) then
        raise EAxonError.Create(SingularMatrix, 'the sparse matrix is singular');
      // Keep the diagonal when it is large enough.
      if (F.Pinv[Col] < 0) and (CAbs(X[Col]) >= PivotTol * A) then
        Ipiv := Col;

      Pivot := X[Ipiv];
      MaxPivot := Max(MaxPivot, CAbs(Pivot));
      MinPivot := Min(MinPivot, CAbs(Pivot));
      GrowU;
      F.Ui[UNz] := K;          // the diagonal of U, last in its column
      F.Ux[UNz] := Pivot;
      Inc(UNz);
      F.Pinv[Ipiv] := K;
      GrowL;
      F.Li[LNz] := Ipiv;       // the diagonal of L, first in its column
      F.Lx[LNz] := Cx(1, 0);
      Inc(LNz);
      for P := Top to N - 1 do
      begin
        I := Xi[P];
        if F.Pinv[I] < 0 then
        begin
          GrowL;
          F.Li[LNz] := I;
          F.Lx[LNz] := CDiv(X[I], Pivot);
          Inc(LNz);
        end;
        X[I] := Cx(0, 0);
      end;
    end;
    F.Lp[N] := LNz;
    F.Up[N] := UNz;
    // Row indices of L in pivot order.
    for P := 0 to LNz - 1 do
      F.Li[P] := F.Pinv[F.Li[P]];
    SetLength(F.Li, LNz);
    SetLength(F.Lx, LNz);
    SetLength(F.Ui, UNz);
    SetLength(F.Ux, UNz);

    if (N > 0) and (MinPivot < MachineEps * MaxPivot) then
      raise EAxonError.Create(SingularMatrix,
        'the sparse matrix is singular to working precision');
  except
    F.Free;
    raise;
  end;
  Result := F;
end;

procedure TSparseLU.Solve(var B: TArray<TComplex>);
var
  X: TArray<TComplex>;
  J, P: Integer;
begin
  SetLength(X, N);
  // x = P b
  for J := 0 to N - 1 do
    X[Pinv[J]] := B[J];
  // L x = x (unit diagonal first)
  for J := 0 to N - 1 do
    for P := Lp[J] + 1 to Lp[J + 1] - 1 do
      X[Li[P]] := CSub(X[Li[P]], CMul(Lx[P], X[J]));
  // U x = x (diagonal last)
  for J := N - 1 downto 0 do
  begin
    X[J] := CDiv(X[J], Ux[Up[J + 1] - 1]);
    for P := Up[J] to Up[J + 1] - 2 do
      X[Ui[P]] := CSub(X[Ui[P]], CMul(Ux[P], X[J]));
  end;
  // b = Q x
  for J := 0 to N - 1 do
    B[Q[J]] := X[J];
end;

end.
