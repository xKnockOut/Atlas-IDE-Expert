unit Atlas.Common.Rules.ProjectFiles;

// Projekte der Gruppe für projektweite Prüfregeln (#1102, unused-public-member):
// Umsetzung von IRuleProjectFiles über den Symbolindex.
//
// - NameIn fragt zuerst die Verwendungen des Index (#492, index.usages, über
//   TIndexUsages). Kann der Index es nicht sagen (index.usages aus, ausgelagert,
//   Unit noch nicht im Index, Wort, das er nicht als Verwendung zählt), sucht
//   NameIn im Text.
// - Units mit Include-Dateien: Was im Text der Unit nicht steht, kann in einer
//   Include-Datei stehen; ist eine davon nicht lesbar, ist die Antwort Unknown.
// - Kind und IsTest leitet KindOfSource bzw. IsTestSource aus dem Hauptquelltext
//   ab, damit die Komposition und der Linter dieselbe Regel anwenden.

interface

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Contract;

type
  /// <summary>Text einer Datei, geöffnete Dokumente zuerst; False, wenn sie nicht lesbar ist.</summary>
  TRuleProjectReadText = reference to function(const AFileName: string; out AText: string): Boolean;
  /// <summary>Sind alle Projekte geladen und indiziert? Sonst der Grund in AReason.</summary>
  TRuleProjectComplete = reference to function(out AReason: string): Boolean;

  TRuleProjectFiles = class(TInterfacedObject, IRuleProjectFiles)
  private
    FProjects: TArray<TRuleProject>;
    FIndex: ISymbolIndex;
    FReadText: TRuleProjectReadText;
    FComplete: TRuleProjectComplete;
    function TextHasName(const AText, AName: string): Boolean;
  public
    /// <summary>AIndex darf nil sein (dann sucht NameIn im Text); AComplete nil = vollständig.</summary>
    constructor Create(const AProjects: TArray<TRuleProject>; const AIndex: ISymbolIndex;
      const AReadText: TRuleProjectReadText; const AComplete: TRuleProjectComplete);
    function Complete(out AReason: string): Boolean;
    function ProjectsOf(const AFileName: string; AWholeGroup: Boolean): TArray<TRuleProject>;
    function NameIn(const AFileName, AName: string): TRuleNameAnswer;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    /// <summary>Art des Projekts aus seinem Hauptquelltext: program, library oder package; .dpk ist immer
    /// ein Package.</summary>
    class function KindOfSource(const AFileName, AText: string): TRuleProjectKind; static;
    /// <summary>Bindet der Hauptquelltext ein Test-Framework ein (DUnitX, DUnit, TestInsight)?</summary>
    class function IsTestSource(const AText: string): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Index.Usages,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Rules.Profiles;

{ TRuleProjectFiles }

constructor TRuleProjectFiles.Create(const AProjects: TArray<TRuleProject>; const AIndex: ISymbolIndex;
  const AReadText: TRuleProjectReadText; const AComplete: TRuleProjectComplete);
begin
  inherited Create;
  FProjects := AProjects;
  FIndex := AIndex;
  FReadText := AReadText;
  FComplete := AComplete;
end;

function TRuleProjectFiles.Complete(out AReason: string): Boolean;
begin
  AReason := '';
  if Assigned(FComplete) then
    Result := FComplete(AReason)
  else
    Result := True;
end;

function TRuleProjectFiles.ProjectsOf(const AFileName: string; AWholeGroup: Boolean): TArray<TRuleProject>;
var
  Project: TRuleProject;
  Source: string;
  Member: Boolean;
  Others: TArray<TRuleProject>;
begin
  Result := nil;
  Others := nil;
  for Project in FProjects do
  begin
    Member := False;
    for Source in Project.Sources do
      if SameText(Source, AFileName) then
        Member := True;
    if Member then
      Result := Result + [Project]
    else
      Others := Others + [Project];
  end;
  if AWholeGroup and (Result <> nil) then
    Result := Result + Others;
end;

function TRuleProjectFiles.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := Assigned(FReadText) and FReadText(AFileName, AText);
end;

function TRuleProjectFiles.TextHasName(const AText, AName: string): Boolean;
var
  Tree: TSyntaxTree;
  Token: TPascalToken;
  Name: string;
begin
  Result := False;
  // Erst billig im Text suchen, dann nur Bezeichner zählen (nicht Kommentare und Strings).
  if not ContainsText(AText, AName) then
    Exit;
  Tree := TSyntaxTreeCache.Parse(AText);
  try
    for Token in Tree.Tokens do
      if Token.Kind = TPascalTokenKind.Identifier then
      begin
        Name := Token.Text;
        if StartsStr('&', Name) then
          Name := Copy(Name, 2, MaxInt);
        if SameText(Name, AName) then
          Exit(True);
      end;
  finally
    Tree.Free;
  end;
end;

function TRuleProjectFiles.NameIn(const AFileName, AName: string): TRuleNameAnswer;
var
  Indexed: TUnitIndex;
  HasUnit: Boolean;
  Text, Include: string;
begin
  HasUnit := (FIndex <> nil) and FIndex.FindFile(AFileName, Indexed);
  if HasUnit then
    // Deklarationen zählen nicht als Verwendung; der Name kann trotzdem als Deklaration in der Datei stehen.
    case TIndexUsages.Lookup(Indexed, AName) of
      TIndexUsageAnswer.Present:
        Exit(TRuleNameAnswer.Present);
      TIndexUsageAnswer.Absent:
        Exit(TRuleNameAnswer.Absent);
    end;
  if not ReadText(AFileName, Text) then
    Exit(TRuleNameAnswer.Unknown);
  if TextHasName(Text, AName) then
    Exit(TRuleNameAnswer.Present);
  if HasUnit then
    for Include in Indexed.Includes do
    begin
      if not ReadText(Include, Text) then
        Exit(TRuleNameAnswer.Unknown);
      if TextHasName(Text, AName) then
        Exit(TRuleNameAnswer.Present);
    end;
  Result := TRuleNameAnswer.Absent;
end;

class function TRuleProjectFiles.KindOfSource(const AFileName, AText: string): TRuleProjectKind;
var
  Tree: TSyntaxTree;
  Token: TPascalToken;
begin
  if SameText(ExtractFileExt(AFileName), '.dpk') then
    Exit(TRuleProjectKind.Package);
  Result := TRuleProjectKind.Unknown;
  Tree := TSyntaxTreeCache.Parse(AText);
  try
    for Token in Tree.Tokens do
      if Token.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword] then
      begin
        if SameText(Token.Text, 'program') then
          Result := TRuleProjectKind.Application
        else if SameText(Token.Text, 'library') then
          Result := TRuleProjectKind.Library_
        else if SameText(Token.Text, 'package') then
          Result := TRuleProjectKind.Package;
        Exit;
      end;
  finally
    Tree.Free;
  end;
end;

class function TRuleProjectFiles.IsTestSource(const AText: string): Boolean;
var
  Tree: TSyntaxTree;
begin
  Tree := TSyntaxTreeCache.Parse(AText);
  try
    Result := TRuleProfiles.IsTestUnit(Tree.Tokens);
  finally
    Tree.Free;
  end;
end;

end.
