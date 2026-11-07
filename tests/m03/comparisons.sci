print(1 < 2, 2 <= 2, 3 > 4, 3 >= 3, 1 == 1, 1 != 1)
print(1 == 1.0, 1 == 1.0 + 0i, 2 < 2.5, true == 1, "a" == "a", "a" < "b", "b" <= "a")
print("1" == 1, nothing == nothing, nothing == 0, 1i == 1i, 1 != "1")
nan = 0.0 / 0.0
print(nan == nan, nan != nan, nan < 1, nan > 1, nan <= nan, 1 == nan)
print(9007199254740993 == 9007199254740992, 9007199254740993 > 9007199254740992)
