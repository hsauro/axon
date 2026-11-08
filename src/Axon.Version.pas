unit Axon.Version;

{ The version of Axon, and of this build: Axon.BuildInfo.inc (gitignored) is
  written by tools\AxonBuildInfo.targets on every build of axon.dproj and
  ide\AxonIDE.dproj, with the build time and the git commit ("+changes" when
  tracked files had uncommitted changes). }

interface

const
  AxonVersion = '0.1.0';
  AxonMilestone = 'L2';

{$I Axon.BuildInfo.inc}

// "0.1.0 (built 2026-11-08 14:05, commit ca4ad60)".
function AxonVersionText: string;

implementation

function AxonVersionText: string;
begin
  Result := AxonVersion + ' (built ' + AxonBuildTime + ', commit ' + AxonCommit + ')';
end;

end.
