unit Atlas.Core.Vcs.BranchNames;

// Branch-Namen ohne VCL, Open Tools API und Netz (#1455, vorher in
// Atlas.Core.Tracker.Naming): Gültigkeit nach git check-ref-format und die
// Basen eines neuen Branchs. Liegt in Base, weil „Branch anlegen“ (#1288,
// Versionsverwaltung) beides braucht, auch ohne das Modul Tracker; „Beginnen“
// (#765) im Tracker nutzt dieselben Regeln.
// - Basen (#1286): issues.branchBase, sonst der Hauptbranch des Projekts
//   (vcs.projects bzw. Abschnitt vcs der .atlas), sonst geraten (Git main,
//   dann master; SVN trunk).

interface

uses
  System.SysUtils;

type
  TAtlasVcsBranchNames = class
  public const
    GitBase = 'main';
    /// <summary>Zweiter Versuch unter Git, wenn es main nicht gibt.</summary>
    GitBaseFallback = 'master';
    SvnBase = 'trunk';
    /// <summary>Höchstlänge eines Branch-Namens.</summary>
    MaxLength = 100;
  public
    /// <summary>Name nach git check-ref-format: nicht leer, ohne Leer- und Steuerzeichen, ~ ^ : ? * [ \, "..",
    /// "@{", "//"; kein "/", "-" oder "." am Anfang, kein "/" oder "." am Ende, kein ".lock" am Ende eines Stücks.
    /// </summary>
    class function Valid(const AName: string): Boolean; static;
    /// <summary>Basen der Reihe nach: ABranchBase (issues.branchBase, ausdrücklich), sonst AMainBranch (Hauptbranch
    /// des Projekts, #1286), sonst geraten: ASvn trunk, Git main und master.</summary>
    class function Bases(ASvn: Boolean; const ABranchBase, AMainBranch: string): TArray<string>; static;
  end;

implementation

class function TAtlasVcsBranchNames.Valid(const AName: string): Boolean;
var
  mIndex: Integer;
  mPart: string;
begin
  Result := False;
  if (AName = '') or CharInSet(AName[1], ['/', '-', '.']) or CharInSet(AName[Length(AName)], ['/', '.']) then
    Exit;
  if (Pos('..', AName) > 0) or (Pos('@{', AName) > 0) or (Pos('//', AName) > 0) or (AName = '@') then
    Exit;
  for mIndex := 1 to Length(AName) do
    case AName[mIndex] of
      #0..' ', '~', '^', ':', '?', '*', '[', '\', #127:
        Exit;
    end;
  for mPart in AName.Split(['/']) do
    if (mPart = '') or (mPart[1] = '.') or SameText(Copy(mPart, Length(mPart) - 4, 5), '.lock') then
      Exit;
  Result := True;
end;

class function TAtlasVcsBranchNames.Bases(ASvn: Boolean; const ABranchBase, AMainBranch: string): TArray<string>;
begin
  if Trim(ABranchBase) <> '' then
    Result := TArray<string>.Create(Trim(ABranchBase))
  else if Trim(AMainBranch) <> '' then
    Result := TArray<string>.Create(Trim(AMainBranch))
  else if ASvn then
    Result := TArray<string>.Create(SvnBase)
  else
    Result := TArray<string>.Create(GitBase, GitBaseFallback);
end;

end.
