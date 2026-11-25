unit Atlas.Common.Projects.GroupProjects;

// Ein Projekt der Gruppe als Wert (TGroupProject, #1102) aus Projektdatei, Hauptquelltext und Units: Art aus dem
// Hauptquelltext (program, library, package), Testprojekt, wenn er ein Test-Framework einbindet, und die
// Formulardateien neben den Units. Komposition, Linter und MCP-Werkzeuge setzen Projekte gleich zusammen.

interface

uses
  Atlas.Common.Projects.Contract.Group;

type
  TGroupProjects = class
  public
    /// <summary>Projekt aus Projektdatei, Hauptquelltext und Units: Art und Testprojekt aus dem Hauptquelltext
    /// (über AReadText), Formulardateien (.dfm, sonst .fmx) neben den Units, sofern sie existieren.</summary>
    class function ProjectOf(const AProjectFile, AMainSource: string; const ASources: TArray<string>;
      const AReadText: TProjectReadText): TGroupProject; static;
    /// <summary>Art des Projekts aus seinem Hauptquelltext: program, library oder package; .dpk ist immer
    /// ein Package.</summary>
    class function KindOfSource(const AFileName, AText: string): TGroupProjectKind; static;
    /// <summary>Bindet der Hauptquelltext ein Test-Framework ein (DUnitX, DUnit, TestInsight)?</summary>
    class function IsTestSource(const AText: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.UsesClauses;

{ TGroupProjects }

class function TGroupProjects.ProjectOf(const AProjectFile, AMainSource: string; const ASources: TArray<string>;
  const AReadText: TProjectReadText): TGroupProject;
var
  mText, mSource: string;
begin
  Result := Default(TGroupProject);
  Result.FileName := AProjectFile;
  Result.Sources := ASources;
  if Assigned(AReadText) and AReadText(AMainSource, mText) then
  begin
    Result.Kind := KindOfSource(AMainSource, mText);
    Result.IsTest := IsTestSource(mText);
  end
  else if SameText(ExtractFileExt(AMainSource), '.dpk') then
  begin
    Result.Kind := TGroupProjectKind.Package;
  end;
  for mSource in ASources do
  begin
    if SameText(ExtractFileExt(mSource), '.pas') then
    begin
      if FileExists(ChangeFileExt(mSource, '.dfm')) then
      begin
        Result.Forms := Result.Forms + [ChangeFileExt(mSource, '.dfm')];
      end
      else if FileExists(ChangeFileExt(mSource, '.fmx')) then
      begin
        Result.Forms := Result.Forms + [ChangeFileExt(mSource, '.fmx')];
      end;
    end;
  end;
end;

class function TGroupProjects.KindOfSource(const AFileName, AText: string): TGroupProjectKind;
var
  mTree: TSyntaxTree;
  mToken: TPascalToken;
begin
  if SameText(ExtractFileExt(AFileName), '.dpk') then
  begin
    Exit(TGroupProjectKind.Package);
  end;
  Result := TGroupProjectKind.Unknown;
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    for mToken in mTree.Tokens do
    begin
      if mToken.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword] then
      begin
        if SameText(mToken.Text, 'program') then
        begin
          Result := TGroupProjectKind.Application;
        end
        else if SameText(mToken.Text, 'library') then
        begin
          Result := TGroupProjectKind.Library_;
        end
        else if SameText(mToken.Text, 'package') then
        begin
          Result := TGroupProjectKind.Package;
        end;
        Exit;
      end;
    end;
  finally
    mTree.Free;
  end;
end;

class function TGroupProjects.IsTestSource(const AText: string): Boolean;
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    Result := TPascalUses.IsTestUnit(mTree.Tokens);
  finally
    mTree.Free;
  end;
end;

end.
