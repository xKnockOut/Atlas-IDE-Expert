unit Atlas.Common.Rules.ProjectFiles;

// Projekte der Gruppe für projektweite Prüfregeln (#1102, unused-public-member):
// Umsetzung von IRuleProjectFiles über den Symbolindex.
//
// - NameIn fragt zuerst die Verwendungen des Index (#492, index.usages): Je
//   Projekt-Unit liegen dort alle Bezeichner außer Deklarationen, sortiert nach
//   dem Namen in Großbuchstaben. Fehlen sie (index.usages aus, ausgelagert, Unit
//   noch nicht im Index) oder ist der Name ein Wort, das der Index nicht als
//   Verwendung zählt (Direktiven, Self, Result), sucht NameIn im Text.
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
    function UsagesHaveName(const AUsages: TArray<TIndexUsage>; const AName: string): Boolean;
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
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Rules.Profiles;

const
  // Wörter, die der Index nicht als Verwendung erfasst (Atlas.Common.Index.Extractor, CollectUsages):
  // Direktiven nach Routinenköpfen sowie Self und Result. Für solche Namen sucht NameIn im Text.
  UncountedWords: array[0..34] of string = (
    'abstract', 'assembler', 'cdecl', 'deprecated', 'dispid', 'dynamic', 'experimental',
    'export', 'external', 'far', 'final', 'forward', 'inline', 'library', 'local',
    'near', 'noreturn', 'overload', 'override', 'pascal', 'platform',
    'register', 'reintroduce', 'safecall', 'static', 'stdcall', 'unsafe', 'varargs',
    'virtual', 'winapi', 'delayed', 'sealed', 'nodefault', 'self', 'result');

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

function TRuleProjectFiles.UsagesHaveName(const AUsages: TArray<TIndexUsage>; const AName: string): Boolean;
var
  Low, High_, Middle, Order: Integer;
  Key: string;
begin
  // Sortiert nach UpperCase(Name), ordinal (TIndexExtractor.CollectUsages).
  Key := UpperCase(AName);
  Low := 0;
  High_ := High(AUsages);
  while Low <= High_ do
  begin
    Middle := (Low + High_) div 2;
    Order := CompareStr(UpperCase(AUsages[Middle].Name), Key);
    if Order = 0 then
      Exit(True);
    if Order < 0 then
      Low := Middle + 1
    else
      High_ := Middle - 1;
  end;
  Result := False;
end;

function TRuleProjectFiles.NameIn(const AFileName, AName: string): TRuleNameAnswer;
var
  Indexed: TUnitIndex;
  HasUnit: Boolean;
  Text, Include: string;
begin
  HasUnit := (FIndex <> nil) and FIndex.FindFile(AFileName, Indexed);
  if HasUnit and Indexed.UsagesIndexed and not Indexed.UsagesOffloaded and
    (IndexText(AName, UncountedWords) < 0) and (Indexed.Includes = nil) then
  begin
    // Deklarationen zählen nicht als Verwendung; der Name kann trotzdem als Deklaration in der Datei stehen.
    if UsagesHaveName(Indexed.Usages, AName) then
      Exit(TRuleNameAnswer.Present);
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
