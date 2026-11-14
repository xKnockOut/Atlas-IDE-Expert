unit Atlas.Common.Rules.Builtin.Collections.Tests;

// Tests der Regel legacy-tlist (#981): Beispiel aus dem Issue, Lesezugriffe
// über Items, First, Last, Extract und as, TObjectList aus Contnrs, lokale
// Variable und Parameter, mehrere Zieltypen, Deklaration in einer anderen
// Unit, stille Fälle (generische Liste, ohne Cast, Pointer, eigene Klasse
// TList, unbekannte Typen) und Einstellungen (Standard aus, off, exclude).
// Schnellkorrektur (#1105): Umwandlung samt Ergebnis, Grund im Befund-Hover,
// Deklaration und Verwendungen in anderen Units der Projektgruppe. Die
// einzelnen Gründe ohne Korrektur prüft Atlas.Common.Editing.GenericLists.Tests.
//
// Tests der Regel legacy-stack-queue (#1106): TStack, TQueue, TObjectStack
// und TObjectQueue aus Contnrs mit Cast über Pop, Peek und as, Meldung je
// Art, mehrere Zieltypen, lokale Variable, Parameter und Feld einer anderen
// Unit, stille Fälle (generische Stapel, ohne Cast, Listen) und Einstellungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLegacyTListTests = class
  public
    [Test]
    procedure IssueExample;
    [Test]
    procedure ReadForms;
    [Test]
    procedure ObjectListLocalsAndParameters;
    [Test]
    procedure SeveralCastTypes;
    [Test]
    procedure DeclaredInOtherUnit;
    [Test]
    procedure SilentCases;
    [Test]
    procedure Settings;
    [Test]
    procedure FixConvertsTheList;
    [Test]
    procedure NoFixGivesReasonInHover;
    [Test]
    procedure FixInDeclaringUnitOfOtherUnit;
    [Test]
    procedure FixFromUnitWithTheCast;
    [Test]
    procedure PropertyLeadsToField;
    [Test]
    procedure OtherUnitsWithoutProject;
  end;

  [TestFixture]
  TLegacyStackQueueTests = class
  public
    [Test]
    procedure IssueExample;
    [Test]
    procedure ReadForms;
    [Test]
    procedure StacksAndQueues;
    [Test]
    procedure SeveralCastTypes;
    [Test]
    procedure LocalsAndOtherUnits;
    [Test]
    procedure SilentCases;
    [Test]
    procedure Settings;
    [Test]
    procedure FixObjectStack;
    [Test]
    procedure FixQueueRenamesMethods;
    [Test]
    procedure NoFixGivesReasonInHover;
    [Test]
    procedure ReferenceProjectMatchesMarkers;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.IOUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.ProjectFiles,
  Atlas.Common.Rules.Builtin.Collections,
  Atlas.Tests.RuleAssert,
  Atlas.Tests.RtlStubs;

const
  cRuleOn = '{"rules": {"legacy-tlist": "info"}}';

const
  cLagerFile = 'C:\Projekt\Lager.pas';
  cAuftraegeFile = 'C:\Projekt\Auftraege.pas';

type
  TProjectFile = record
    Name: string;
    Text: string;
  end;

/// <summary>System, System.Classes, System.Contnrs und System.Generics.Collections als Stubs.</summary>
function BaseIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  TRtlStubs.AddTo(Result);
end;

function RtlIndex: ISymbolIndex;
begin
  Result := BaseIndex;
  Result.AddUnit(TIndexExtractor.ExtractText('unit Lager;'#10'interface'#10'uses'#10'  System.Classes;'#10 +
    'type'#10'  TLager = class'#10'  public'#10'    Regale: TList;'#10'  end;'#10'implementation'#10'end.',
    'C:\Projekt\Lager.pas', nil));
end;

function Findings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TLegacyTListRule.Create, ASource, RtlIndex, cRuleOn, 'Auftraege.pas');
end;

function Findings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TLegacyTListRule.Create, ASource, RtlIndex, AConfig, APath);
end;

/// <summary>Unit mit TPosition und TAuftrag (Feld FPositionen vom Typ AListType); AStatements in TAuftrag.Summe.
/// </summary>
function Auftrag(const AUses, AListType, AStatements: string): string;
begin
  Result := 'unit Auftraege;'#10'interface'#10'uses'#10'  ' + AUses + ';'#10'type'#10'  TPosition = class'#10 +
    '  end;'#10'  TAuftrag = class'#10'  private'#10'    FPositionen: ' + AListType + ';'#10'  public'#10 +
    '    procedure Summe;'#10'  end;'#10'implementation'#10'procedure TAuftrag.Summe;'#10'var'#10 +
    '  I: Integer;'#10'  Pos: TPosition;'#10'  Obj: TObject;'#10'begin'#10 + AStatements + 'end;'#10'end.';
end;

function ProjectFile(const AName, AText: string): TProjectFile;
begin
  Result.Name := AName;
  Result.Text := AText;
end;

/// <summary>Treffer für ACheck in einer Anwendung aus AFiles, mit Projektdateien wie im Server (#1102).</summary>
function ProjectFindings(const AFiles: TArray<TProjectFile>; const ACheck: string;
  AComplete: Boolean): TArray<TRuleFinding>;
var
  mTexts: TDictionary<string, string>;
  mIndex: ISymbolIndex;
  mEntry: TProjectFile;
  mProject: TRuleProject;
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
  mContext: TRuleContext;
  mTree: TSyntaxTree;
  mText: string;
  mComplete: Boolean;
begin
  mComplete := AComplete;
  mTexts := TDictionary<string, string>.Create;
  try
    mIndex := BaseIndex;
    mProject := Default(TRuleProject);
    mProject.FileName := 'C:\Projekt\App.dproj';
    mProject.Kind := TRuleProjectKind.Application;
    for mEntry in AFiles do
    begin
      mTexts.AddOrSetValue(UpperCase(mEntry.Name), mEntry.Text);
      mIndex.AddUnit(TIndexExtractor.ExtractText(mEntry.Text, mEntry.Name, nil));
      mProject.Sources := mProject.Sources + [mEntry.Name];
    end;
    mSettings := TConfigurationParser.Parse(cRuleOn, mIssues);
    mTexts.TryGetValue(UpperCase(ACheck), mText);
    mTree := TSyntaxTreeCache.Parse(mText);
    try
      mContext := Default(TRuleContext);
      mContext.FileName := ACheck;
      mContext.RelativePath := ExtractFileName(ACheck);
      mContext.UnitName := ChangeFileExt(ExtractFileName(ACheck), '');
      mContext.Text := mText;
      mContext.Tree := mTree;
      mContext.Index := mIndex;
      mContext.ProjectFiles := TRuleProjectFiles.Create([mProject], mIndex,
        function(const AFileName: string; out AText: string): Boolean
        begin
          Result := mTexts.TryGetValue(UpperCase(AFileName), AText);
        end,
        function(out AReason: string): Boolean
        begin
          Result := mComplete;
          if not mComplete then
          begin
            AReason := 'Index läuft (1 von 2 Units)';
          end;
        end);
      Result := TRuleEngine.Run([TLegacyTListRule.Create], mSettings, mContext);
      mContext.ProjectFiles := nil;
    finally
      mTree.Free;
    end;
  finally
    mTexts.Free;
  end;
end;

/// <summary>Lager mit TRegal und dem öffentlichen Feld Regale: TList (bzw. ADeclaration in TLager).</summary>
function LagerText(const ADeclaration: string): string;
begin
  Result := 'unit Lager;'#10'interface'#10'uses'#10'  System.Classes;'#10'type'#10'  TRegal = class'#10'  end;'#10 +
    '  TLager = class'#10 + ADeclaration + '    constructor Create;'#10'  end;'#10'implementation'#10 +
    'constructor TLager.Create;'#10'begin'#10'  Regale := TList.Create;'#10'end;'#10'end.';
end;

/// <summary>Auftraege liest Lager.Regale mit Cast; AMore sind weitere Anweisungen.</summary>
function AuftraegeText(const AMore: string): string;
begin
  Result := 'unit Auftraege;'#10'interface'#10'uses'#10'  Lager;'#10'implementation'#10 +
    'procedure Lesen(L: TLager);'#10'var'#10'  R: TRegal;'#10'begin'#10'  R := TRegal(L.Regale[0]);'#10 + AMore +
    'end;'#10'end.';
end;

const
  cPublicRegale = '  public'#10'    Regale: TList;'#10;

procedure AssertContains(const AText, APart: string);
begin
  Assert.IsTrue(Pos(APart, AText) > 0, Format('"%s" fehlt in:'#10'%s', [APart, AText]));
end;

procedure TLegacyTListTests.IssueExample;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(Auftrag('System.Classes', 'TList', '  Pos := TPosition(FPositionen[I]);'#10));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Ungenerische TList mit Cast beim Lesen; TList<TPosition> prüft den Typ beim Übersetzen.',
    mFound[0].Message);
  // An der Deklaration des Felds.
  Assert.AreEqual(9, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(4, mFound[0].Range.StartPos.Character);
  // Schnellkorrektur (#1105).
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)));
  Assert.AreEqual('In TList<TPosition> umwandeln', mFound[0].Fixes[0].Title);
  // Mit System.Generics.Collections hinter System.Classes bleibt TList die ungenerische Klasse.
  Assert.AreEqual(1, Integer(Length(Findings(Auftrag('System.Classes, System.Generics.Collections', 'TList',
    '  Pos := TPosition(FPositionen[I]);'#10)))));
  // Die korrigierte Form ist still.
  Assert.AreEqual(0, Integer(Length(Findings(Auftrag('System.Classes, System.Generics.Collections',
    'TList<TPosition>', '  Pos := FPositionen[I];'#10)))));
end;

procedure TLegacyTListTests.ReadForms;
var
  mStatement: string;
  mFound: TArray<TRuleFinding>;
  mIndex: ISymbolIndex;
begin
  for mStatement in ['  Pos := TPosition(FPositionen.Items[I]);'#10, '  Pos := TPosition(FPositionen.First);'#10,
    '  Pos := TPosition(FPositionen.Last());'#10, '  Pos := TPosition(Self.FPositionen[I]);'#10,
    '  Pos := FPositionen[I] as TPosition;'#10, '  Pos := (FPositionen[I]) as TPosition;'#10,
    '  if TPosition(FPositionen[0]) = nil then'#10'    Exit;'#10,
    '  Pos := TPosition(FPositionen.Extract(Pos));'#10] do
  begin
    mFound := Findings(Auftrag('System.Classes', 'TList', mStatement));
    Assert.AreEqual(1, Integer(Length(mFound)), mStatement);
    Assert.AreEqual(9, mFound[0].Range.StartPos.Line, mStatement);
  end;
  // Mehrere Casts derselben Liste: ein Treffer.
  mFound := Findings(Auftrag('System.Classes', 'TList', '  Pos := TPosition(FPositionen[0]);'#10 +
    '  Pos := TPosition(FPositionen.Last);'#10));
  Assert.AreEqual(1, Integer(Length(mFound)));
  // RTL-Quellen ohne Namespace (Classes statt System.Classes).
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit Classes;'#10'interface'#10'type'#10'  TList = class'#10 +
    '  public'#10'    function Get(Index: Integer): Pointer;'#10 +
    '    property Items[Index: Integer]: Pointer read Get; default;'#10'  end;'#10'implementation'#10'end.',
    'C:\Alt\Classes.pas', nil));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.IndexFindings(TLegacyTListRule.Create,
    Auftrag('Classes', 'TList', '  Pos := TPosition(FPositionen[I]);'#10), mIndex, cRuleOn, 'Auftraege.pas'))));
end;

procedure TLegacyTListTests.ObjectListLocalsAndParameters;
var
  mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(Auftrag('System.Classes, System.Contnrs', 'TObjectList',
    '  Pos := TPosition(FPositionen[I]);'#10));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Ungenerische TObjectList mit Cast beim Lesen; TObjectList<TPosition> prüft den Typ beim ' +
    'Übersetzen.', mFound[0].Message);
  // Lokale Variable und Parameter: je Deklaration ein Treffer an ihrem Namen.
  mSource := 'unit Auftraege;'#10'interface'#10'uses'#10'  System.Classes;'#10'type'#10'  TPosition = class'#10 +
    '  end;'#10'implementation'#10'procedure Lesen(Quelle: TList);'#10'var'#10'  Ziel: TList;'#10 +
    '  Pos: TPosition;'#10'begin'#10'  Pos := TPosition(Quelle[0]);'#10'  Pos := TPosition(Ziel.First);'#10 +
    'end;'#10'end.';
  mFound := Findings(mSource);
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual(8, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(16, mFound[0].Range.StartPos.Character);
  Assert.AreEqual(10, mFound[1].Range.StartPos.Line);
  Assert.AreEqual(2, mFound[1].Range.StartPos.Character);
end;

procedure TLegacyTListTests.SeveralCastTypes;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(Auftrag('System.Classes', 'TList', '  Pos := TPosition(FPositionen[0]);'#10 +
    '  Obj := TObject(FPositionen[1]);'#10));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Ungenerische TList mit Casts auf TPosition, TObject beim Lesen; eine generische Liste prüft den ' +
    'Typ beim Übersetzen.', mFound[0].Message);
end;

procedure TLegacyTListTests.DeclaredInOtherUnit;
var
  mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  // Das Feld steht in Lager: der Treffer sitzt am Cast dieser Datei.
  mSource := 'unit Auftraege;'#10'interface'#10'uses'#10'  System.Classes, Lager;'#10'type'#10 +
    '  TPosition = class'#10'  end;'#10'implementation'#10'procedure Lesen(L: TLager);'#10'var'#10 +
    '  Pos: TPosition;'#10'begin'#10'  Pos := TPosition(L.Regale[0]);'#10'end;'#10'end.';
  mFound := Findings(mSource);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(12, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(9, mFound[0].Range.StartPos.Character);
  Assert.AreEqual(12, mFound[0].Range.EndPos.Line);
  Assert.AreEqual(31, mFound[0].Range.EndPos.Character);
end;

procedure TLegacyTListTests.SilentCases;
var
  mStatement: string;
begin
  for mStatement in [
    // Ohne Cast, Pointer, Funktionsaufruf statt Cast, unbekannter Typ.
    '  I := FPositionen.Count;'#10'  FPositionen.Add(Pos);'#10, '  Obj := Pointer(FPositionen[I]);'#10,
    '  Pos := Umwandeln(FPositionen[I]);'#10, '  Pos := TUnbekannt(FPositionen[I]);'#10,
    // Cast auf etwas anderes als die Liste.
    '  Pos := TPosition(Obj);'#10] do
  begin
    Assert.AreEqual(0, Integer(Length(Findings(Auftrag('System.Classes', 'TList', mStatement).Replace('begin'#10,
      'function Umwandeln(P: Pointer): TPosition;'#10'begin'#10'end;'#10#10'begin'#10)))), mStatement);
  end;
  // Generische Liste mit überflüssigem Cast: nicht diese Regel.
  Assert.AreEqual(0, Integer(Length(Findings(Auftrag('System.Generics.Collections', 'TList<TObject>',
    '  Pos := TPosition(FPositionen[I]);'#10)))));
  // TStringList.Objects ist keine ungenerische Liste.
  Assert.AreEqual(0, Integer(Length(Findings(Auftrag('System.Classes', 'TStrings',
    '  Pos := TPosition(FPositionen.Objects[I]);'#10)))));
  // Eigene Klasse TList in der Unit.
  Assert.AreEqual(0, Integer(Length(Findings(Auftrag('System.Classes', 'TList',
    '  Pos := TPosition(FPositionen[I]);'#10).Replace('  TPosition = class'#10,
    '  TList = class'#10'    function Get(Index: Integer): TObject;'#10 +
    '    property Items[Index: Integer]: TObject read Get; default;'#10'  end;'#10'  TPosition = class'#10)))));
  // Ohne Index keine Aussage.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.IndexFindings(TLegacyTListRule.Create,
    Auftrag('System.Classes', 'TList', '  Pos := TPosition(FPositionen[I]);'#10), nil, cRuleOn, 'Auftraege.pas'))));
end;

procedure TLegacyTListTests.Settings;
var
  mSource: string;
begin
  mSource := Auftrag('System.Classes', 'TList', '  Pos := TPosition(FPositionen[I]);'#10);
  // Standard aus.
  Assert.AreEqual(0, Integer(Length(Findings(mSource, '', 'Source/Auftraege.pas'))));
  Assert.AreEqual(1, Integer(Length(Findings(mSource, cRuleOn, 'Source/Auftraege.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(mSource, '{"rules": {"legacy-tlist": "off"}}', 'Source/Auftraege.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(mSource,
    '{"rules": {"legacy-tlist": {"severity": "info", "exclude": ["Source/*.pas"]}}}', 'Source/Auftraege.pas'))));
  Assert.AreEqual(1, Integer(Length(Findings(mSource,
    '{"rules": {"legacy-tlist": {"severity": "info", "exclude": ["Alt/*.pas"]}}}', 'Source/Auftraege.pas'))));
end;

procedure TLegacyTListTests.FixConvertsTheList;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Auftrag('System.Classes', 'TList', '  FPositionen := TList.Create;'#10 +
    '  Pos := TPosition(FPositionen[I]);'#10'  Pos := FPositionen.First as TPosition;'#10);
  mFound := Findings(mSource);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)));
  Assert.AreEqual('', mFound[0].Details);
  // Nur diese Datei, alle Typen bekannt: auch für source.fixAll.
  Assert.IsTrue(mFound[0].Fixes[0].Safe);
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes[0].OtherFiles)));
  mFixed := TChangeSignature.ApplyEdits(mSource, mFound[0].Fixes[0].Edits);
  AssertContains(mFixed, '  System.Classes,'#10'  System.Generics.Collections;'#10);
  AssertContains(mFixed, '    FPositionen: TList<TPosition>;'#10);
  AssertContains(mFixed, '  FPositionen := TList<TPosition>.Create;'#10);
  AssertContains(mFixed, '  Pos := FPositionen[I];'#10'  Pos := FPositionen.First;'#10);
  // Das Ergebnis meldet die Regel nicht mehr.
  Assert.AreEqual(0, Integer(Length(Findings(mFixed))));
end;

procedure TLegacyTListTests.NoFixGivesReasonInHover;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(Auftrag('System.Classes', 'TList', '  FPositionen.Sort(Vergleichen);'#10 +
    '  Pos := TPosition(FPositionen[I]);'#10));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
  Assert.IsTrue(StartsStr('Keine Schnellkorrektur: ', mFound[0].Details), mFound[0].Details);
  AssertContains(mFound[0].Details, 'TListSortCompare');
  // Verschiedene Casts derselben Liste.
  mFound := Findings(Auftrag('System.Classes', 'TList', '  Pos := TPosition(FPositionen[0]);'#10 +
    '  Obj := TObject(FPositionen[1]);'#10));
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
  AssertContains(mFound[0].Details, 'TPosition');
end;

procedure TLegacyTListTests.FixInDeclaringUnitOfOtherUnit;
var
  mFiles: TArray<TProjectFile>;
  mFound: TArray<TRuleFinding>;
  mFix: TRuleFix;
begin
  // Das öffentliche Feld wird in Auftraege gelesen: beide Units ändern sich, also nicht Safe.
  mFiles := [ProjectFile(cLagerFile, LagerText(cPublicRegale)), ProjectFile(cAuftraegeFile, AuftraegeText(''))];
  mFound := ProjectFindings(mFiles, cLagerFile, True);
  Assert.AreEqual(0, Integer(Length(mFound)), 'Lager selbst liest nicht mit Cast');
  mFound := ProjectFindings(mFiles, cAuftraegeFile, True);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)), mFound[0].Details);
  mFix := mFound[0].Fixes[0];
  Assert.AreEqual('In TList<TRegal> umwandeln', mFix.Title);
  Assert.IsFalse(mFix.Safe);
  AssertContains(TChangeSignature.ApplyEdits(mFiles[1].Text, mFix.Edits), '  R := L.Regale[0];'#10);
  Assert.AreEqual(1, Integer(Length(mFix.OtherFiles)));
  Assert.AreEqual(cLagerFile, mFix.OtherFiles[0].FileName);
  AssertContains(TChangeSignature.ApplyEdits(mFiles[0].Text, mFix.OtherFiles[0].Edits),
    '  System.Classes,'#10'  System.Generics.Collections;'#10);
  AssertContains(TChangeSignature.ApplyEdits(mFiles[0].Text, mFix.OtherFiles[0].Edits),
    '    Regale: TList<TRegal>;'#10);
  AssertContains(TChangeSignature.ApplyEdits(mFiles[0].Text, mFix.OtherFiles[0].Edits),
    '  Regale := TList<TRegal>.Create;'#10);
end;

procedure TLegacyTListTests.FixFromUnitWithTheCast;
var
  mFiles: TArray<TProjectFile>;
  mFound: TArray<TRuleFinding>;
begin
  // Eine weitere Unit nutzt Sort: keine Korrektur, der Grund nennt es.
  mFiles := [ProjectFile(cLagerFile, LagerText(cPublicRegale)),
    ProjectFile(cAuftraegeFile, AuftraegeText('  L.Regale.Sort(Vergleichen);'#10))];
  mFound := ProjectFindings(mFiles, cAuftraegeFile, True);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
  AssertContains(mFound[0].Details, 'TListSortCompare');
  // Projekt noch nicht fertig geladen.
  mFiles := [ProjectFile(cLagerFile, LagerText(cPublicRegale)), ProjectFile(cAuftraegeFile, AuftraegeText(''))];
  mFound := ProjectFindings(mFiles, cAuftraegeFile, False);
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
  AssertContains(mFound[0].Details, 'Index läuft');
end;

procedure TLegacyTListTests.PropertyLeadsToField;
var
  mFiles: TArray<TProjectFile>;
  mFound: TArray<TRuleFinding>;
  mFixed: string;
begin
  // L.Regale ist eine Property, die das private Feld liest: umgewandelt werden Feld und Property.
  mFiles := [ProjectFile(cLagerFile, LagerText('  private'#10'    FRegale: TList;'#10'  public'#10 +
    '    property Regale: TList read FRegale;'#10).Replace('  Regale := TList.Create;', '  FRegale := TList.Create;')),
    ProjectFile(cAuftraegeFile, AuftraegeText(''))];
  mFound := ProjectFindings(mFiles, cAuftraegeFile, True);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)), mFound[0].Details);
  mFixed := TChangeSignature.ApplyEdits(mFiles[0].Text, mFound[0].Fixes[0].OtherFiles[0].Edits);
  AssertContains(mFixed, '    FRegale: TList<TRegal>;'#10);
  AssertContains(mFixed, '    property Regale: TList<TRegal> read FRegale;'#10);
  AssertContains(mFixed, '  FRegale := TList<TRegal>.Create;'#10);
end;

procedure TLegacyTListTests.OtherUnitsWithoutProject;
var
  mFound: TArray<TRuleFinding>;
begin
  // Ohne Projekt (Linter): Die Deklaration in Lager lässt sich nicht ändern, der Grund steht im Hover.
  mFound := Findings('unit Auftraege;'#10'interface'#10'uses'#10'  System.Classes, Lager;'#10'type'#10 +
    '  TPosition = class'#10'  end;'#10'implementation'#10'procedure Lesen(L: TLager);'#10'var'#10 +
    '  Pos: TPosition;'#10'begin'#10'  Pos := TPosition(L.Regale[0]);'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
  AssertContains(mFound[0].Details, 'ohne geladenes Projekt');
  // Öffentliches Feld dieser Unit: andere Units sind ohne Projekt nicht prüfbar.
  mFound := Findings(Auftrag('System.Classes', 'TList', '  Pos := TPosition(FPositionen[I]);'#10).Replace(
    '  private'#10'    FPositionen', '  public'#10'    FPositionen'));
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
  AssertContains(mFound[0].Details, 'in anderen Units sichtbar');
end;

{ TLegacyStackQueueTests }

const
  cStackQueueOn = '{"rules": {"legacy-stack-queue": "info"}}';

function StackFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TLegacyStackQueueRule.Create, ASource, RtlIndex, cStackQueueOn, 'Suche.pas');
end;

function StackFindings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TLegacyStackQueueRule.Create, ASource, RtlIndex, AConfig, APath);
end;

/// <summary>Unit mit TKnoten und TSuche (Feld FOffen vom Typ AType); AStatements in TSuche.Lauf.</summary>
/// <summary>RTL ohne Namespaces (ältere Delphi-Versionen): Contnrs mit TObjectStack.</summary>
function OldRtlIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText('unit Contnrs;'#10'interface'#10'type'#10'  TObjectStack = class'#10 +
    '  public'#10'    function Pop: TObject;'#10'  end;'#10'implementation'#10'end.', 'C:\Alt\Contnrs.pas', nil));
end;

function Suche(const AUses, AType, AStatements: string): string;
begin
  Result := 'unit Suche;'#10'interface'#10'uses'#10'  ' + AUses + ';'#10'type'#10'  TKnoten = class'#10 +
    '  end;'#10'  TSuche = class'#10'  private'#10'    FOffen: ' + AType + ';'#10'  public'#10 +
    '    procedure Lauf;'#10'  end;'#10'implementation'#10'procedure TSuche.Lauf;'#10'var'#10 +
    '  Knoten: TKnoten;'#10'  Obj: TObject;'#10'begin'#10 + AStatements + 'end;'#10'end.';
end;

procedure TLegacyStackQueueTests.IssueExample;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := StackFindings(Suche('System.Contnrs', 'TObjectStack', '  Knoten := TKnoten(FOffen.Pop);'#10));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Ungenerischer TObjectStack mit Cast beim Lesen; TObjectStack<TKnoten> prüft den Typ beim ' +
    'Übersetzen.', mFound[0].Message);
  // An der Deklaration des Felds.
  Assert.AreEqual(9, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(4, mFound[0].Range.StartPos.Character);
  // System.Generics.Collections hinter System.Contnrs: TObjectStack bleibt die ungenerische Klasse.
  Assert.AreEqual(1, Integer(Length(StackFindings(Suche('System.Contnrs, System.Generics.Collections',
    'TObjectStack', '  Knoten := TKnoten(FOffen.Pop);'#10)))));
  // Die korrigierte Form ist still.
  Assert.AreEqual(0, Integer(Length(StackFindings(Suche('System.Contnrs, System.Generics.Collections',
    'TObjectStack<TKnoten>', '  Knoten := FOffen.Pop;'#10)))));
end;

procedure TLegacyStackQueueTests.ReadForms;
var
  mStatement: string;
  mFound: TArray<TRuleFinding>;
begin
  for mStatement in ['  Knoten := TKnoten(FOffen.Peek);'#10, '  Knoten := TKnoten(FOffen.Pop());'#10,
    '  Knoten := TKnoten(Self.FOffen.Pop);'#10, '  Knoten := FOffen.Pop as TKnoten;'#10,
    '  Knoten := (FOffen.Peek) as TKnoten;'#10, '  if TKnoten(FOffen.Peek) = nil then'#10'    Exit;'#10] do
  begin
    mFound := StackFindings(Suche('System.Contnrs', 'TObjectStack', mStatement));
    Assert.AreEqual(1, Integer(Length(mFound)), mStatement);
    Assert.AreEqual(9, mFound[0].Range.StartPos.Line, mStatement);
  end;
  // Mehrere Casts desselben Stapels: ein Treffer.
  mFound := StackFindings(Suche('System.Contnrs', 'TObjectStack', '  Knoten := TKnoten(FOffen.Peek);'#10 +
    '  Knoten := TKnoten(FOffen.Pop);'#10));
  Assert.AreEqual(1, Integer(Length(mFound)));
end;

procedure TLegacyStackQueueTests.StacksAndQueues;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := StackFindings(Suche('System.Contnrs', 'TStack', '  Knoten := TKnoten(FOffen.Pop);'#10));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Ungenerischer TStack mit Cast beim Lesen; TStack<TKnoten> prüft den Typ beim Übersetzen.',
    mFound[0].Message);
  mFound := StackFindings(Suche('System.Contnrs', 'TQueue', '  Knoten := TKnoten(FOffen.Pop);'#10));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Ungenerische TQueue mit Cast beim Lesen; TQueue<TKnoten> prüft den Typ beim Übersetzen.',
    mFound[0].Message);
  mFound := StackFindings(Suche('System.Contnrs', 'TObjectQueue', '  Knoten := TKnoten(FOffen.Peek);'#10));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Ungenerische TObjectQueue mit Cast beim Lesen; TObjectQueue<TKnoten> prüft den Typ beim ' +
    'Übersetzen.', mFound[0].Message);
  // RTL-Quellen ohne Namespace (Contnrs statt System.Contnrs).
  Assert.AreEqual(1, Integer(Length(TRuleAssert.IndexFindings(TLegacyStackQueueRule.Create,
    Suche('Contnrs', 'TObjectStack', '  Knoten := TKnoten(FOffen.Pop);'#10), OldRtlIndex, cStackQueueOn,
    'Suche.pas'))));
end;

procedure TLegacyStackQueueTests.SeveralCastTypes;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := StackFindings(Suche('System.Contnrs', 'TObjectStack', '  Knoten := TKnoten(FOffen.Pop);'#10 +
    '  Obj := TObject(FOffen.Pop);'#10));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Ungenerischer TObjectStack mit Casts auf TKnoten, TObject beim Lesen; ein generischer Stapel ' +
    'prüft den Typ beim Übersetzen.', mFound[0].Message);
  mFound := StackFindings(Suche('System.Contnrs', 'TQueue', '  Knoten := TKnoten(FOffen.Pop);'#10 +
    '  Obj := TObject(FOffen.Peek);'#10));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Ungenerische TQueue mit Casts auf TKnoten, TObject beim Lesen; eine generische Warteschlange ' +
    'prüft den Typ beim Übersetzen.', mFound[0].Message);
end;

procedure TLegacyStackQueueTests.LocalsAndOtherUnits;
var
  mSource: string;
  mFound: TArray<TRuleFinding>;
  mIndex: ISymbolIndex;
begin
  // Lokale Variable und Parameter: je Deklaration ein Treffer an ihrem Namen.
  mSource := 'unit Suche;'#10'interface'#10'uses'#10'  System.Contnrs;'#10'type'#10'  TKnoten = class'#10 +
    '  end;'#10'implementation'#10'procedure Lesen(Quelle: TObjectQueue);'#10'var'#10'  Ziel: TStack;'#10 +
    '  Knoten: TKnoten;'#10'begin'#10'  Knoten := TKnoten(Quelle.Pop);'#10'  Knoten := TKnoten(Ziel.Peek);'#10 +
    'end;'#10'end.';
  mFound := StackFindings(mSource);
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual(8, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(16, mFound[0].Range.StartPos.Character);
  Assert.AreEqual(10, mFound[1].Range.StartPos.Line);
  Assert.AreEqual(2, mFound[1].Range.StartPos.Character);
  // Das Feld steht in einer anderen Unit: der Treffer sitzt am Cast dieser Datei.
  mIndex := RtlIndex;
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit Ablage;'#10'interface'#10'uses'#10'  System.Contnrs;'#10 +
    'type'#10'  TAblage = class'#10'  public'#10'    Stapel: TObjectStack;'#10'  end;'#10'implementation'#10'end.',
    'C:\Projekt\Ablage.pas', nil));
  mSource := 'unit Suche;'#10'interface'#10'uses'#10'  System.Contnrs, Ablage;'#10'type'#10'  TKnoten = class'#10 +
    '  end;'#10'implementation'#10'procedure Lesen(A: TAblage);'#10'var'#10'  Knoten: TKnoten;'#10'begin'#10 +
    '  Knoten := TKnoten(A.Stapel.Pop);'#10'end;'#10'end.';
  mFound := TRuleAssert.IndexFindings(TLegacyStackQueueRule.Create, mSource, mIndex, cStackQueueOn, 'Suche.pas');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(12, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(12, mFound[0].Range.StartPos.Character);
end;

procedure TLegacyStackQueueTests.SilentCases;
var
  mStatement: string;
begin
  for mStatement in [
    // Ohne Cast, Pointer, unbekannter Typ, Cast auf etwas anderes als den Stapel.
    '  FOffen.Push(Knoten);'#10'  if FOffen.Count = 0 then'#10'    Exit;'#10'  FOffen.Pop;'#10,
    '  Obj := Pointer(FOffen.Pop);'#10, '  Knoten := TUnbekannt(FOffen.Pop);'#10, '  Knoten := TKnoten(Obj);'#10] do
  begin
    Assert.AreEqual(0, Integer(Length(StackFindings(Suche('System.Contnrs', 'TObjectStack', mStatement)))), mStatement);
  end;
  // Generischer Stapel und generische Warteschlange mit überflüssigem Cast: nicht diese Regel.
  Assert.AreEqual(0, Integer(Length(StackFindings(Suche('System.Generics.Collections', 'TStack<TObject>',
    '  Knoten := TKnoten(FOffen.Pop);'#10)))));
  Assert.AreEqual(0, Integer(Length(StackFindings(Suche('System.Generics.Collections', 'TQueue<TObject>',
    '  Knoten := TKnoten(FOffen.Dequeue);'#10)))));
  // Listen sind legacy-tlist, Stapel nicht legacy-tlist.
  Assert.AreEqual(0, Integer(Length(StackFindings(Suche('System.Contnrs', 'TObjectList',
    '  Knoten := TKnoten(FOffen[0]);'#10)))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.IndexFindings(TLegacyTListRule.Create,
    Suche('System.Contnrs', 'TObjectStack', '  Knoten := TKnoten(FOffen.Pop);'#10), RtlIndex,
    '{"rules": {"legacy-tlist": "info"}}', 'Suche.pas'))));
  // Eigene Klasse TObjectStack in der Unit.
  Assert.AreEqual(0, Integer(Length(StackFindings(Suche('System.Contnrs', 'TObjectStack',
    '  Knoten := TKnoten(FOffen.Pop);'#10).Replace('  TKnoten = class'#10,
    '  TObjectStack = class'#10'    function Pop: TObject;'#10'  end;'#10'  TKnoten = class'#10)))));
  // Ohne Index keine Aussage.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.IndexFindings(TLegacyStackQueueRule.Create,
    Suche('System.Contnrs', 'TObjectStack', '  Knoten := TKnoten(FOffen.Pop);'#10), nil, cStackQueueOn,
    'Suche.pas'))));
end;

procedure TLegacyStackQueueTests.Settings;
var
  mSource: string;
begin
  mSource := Suche('System.Contnrs', 'TObjectStack', '  Knoten := TKnoten(FOffen.Pop);'#10);
  // Standard aus.
  Assert.AreEqual(0, Integer(Length(StackFindings(mSource, '', 'Source/Suche.pas'))));
  Assert.AreEqual(1, Integer(Length(StackFindings(mSource, cStackQueueOn, 'Source/Suche.pas'))));
  Assert.AreEqual(0, Integer(Length(StackFindings(mSource, '{"rules": {"legacy-stack-queue": "off"}}',
    'Source/Suche.pas'))));
  Assert.AreEqual(0, Integer(Length(StackFindings(mSource,
    '{"rules": {"legacy-stack-queue": {"severity": "info", "exclude": ["Source/*.pas"]}}}', 'Source/Suche.pas'))));
  Assert.AreEqual(1, Integer(Length(StackFindings(mSource,
    '{"rules": {"legacy-stack-queue": {"severity": "info", "exclude": ["Alt/*.pas"]}}}', 'Source/Suche.pas'))));
end;

procedure AssertParses(const AText: string);
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)), AText);
  finally
    mTree.Free;
  end;
end;

procedure TLegacyStackQueueTests.FixObjectStack;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  // Das Beispiel aus #1106 mit Create: TObjectStack<T> besitzt seine Objekte, daher Create(False). Pop ist bei
  // TObjectStack<T> eine Prozedur, die das Objekt freigibt; das Element ohne Freigabe liefert Extract.
  mSource := Suche('System.Contnrs', 'TObjectStack', '  FOffen := TObjectStack.Create;'#10 +
    '  FOffen.Push(Knoten);'#10'  Knoten := TKnoten(FOffen.Pop);'#10'  Knoten := FOffen.Peek as TKnoten;'#10);
  mFound := StackFindings(mSource);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)), mFound[0].Details);
  Assert.AreEqual('In TObjectStack<TKnoten> umwandeln', mFound[0].Fixes[0].Title);
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes[0].OtherFiles)));
  mFixed := TChangeSignature.ApplyEdits(mSource, mFound[0].Fixes[0].Edits);
  // System.Contnrs wird nicht mehr gebraucht.
  AssertContains(mFixed, 'uses'#10'  System.Generics.Collections;'#10);
  AssertContains(mFixed, '    FOffen: TObjectStack<TKnoten>;'#10);
  AssertContains(mFixed, '  FOffen := TObjectStack<TKnoten>.Create(False);'#10);
  AssertContains(mFixed, '  FOffen.Push(Knoten);'#10'  Knoten := FOffen.Extract;'#10'  Knoten := FOffen.Peek;'#10);
  AssertParses(mFixed);
  // Das Ergebnis meldet die Regel nicht mehr.
  Assert.AreEqual(0, Integer(Length(StackFindings(mFixed))));
  // TStack besitzt nichts: Create bleibt, Pop bleibt.
  mSource := Suche('System.Contnrs', 'TStack', '  FOffen := TStack.Create;'#10 +
    '  Knoten := TKnoten(FOffen.Pop);'#10);
  mFound := StackFindings(mSource);
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)), mFound[0].Details);
  mFixed := TChangeSignature.ApplyEdits(mSource, mFound[0].Fixes[0].Edits);
  AssertContains(mFixed, '  FOffen := TStack<TKnoten>.Create;'#10'  Knoten := FOffen.Pop;'#10);
  AssertParses(mFixed);
end;

procedure TLegacyStackQueueTests.FixQueueRenamesMethods;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  // TQueue<T> heißt Enqueue/Dequeue statt Push/Pop.
  mSource := Suche('System.Contnrs', 'TQueue', '  FOffen := TQueue.Create;'#10'  FOffen.Push(Knoten);'#10 +
    '  Knoten := TKnoten(FOffen.Pop);'#10);
  mFound := StackFindings(mSource);
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)), mFound[0].Details);
  Assert.AreEqual('In TQueue<TKnoten> umwandeln', mFound[0].Fixes[0].Title);
  mFixed := TChangeSignature.ApplyEdits(mSource, mFound[0].Fixes[0].Edits);
  AssertContains(mFixed, '    FOffen: TQueue<TKnoten>;'#10);
  AssertContains(mFixed, '  FOffen := TQueue<TKnoten>.Create;'#10'  FOffen.Enqueue(Knoten);'#10 +
    '  Knoten := FOffen.Dequeue;'#10);
  AssertParses(mFixed);
  // TObjectQueue: Create(False), Enqueue und Extract.
  mSource := Suche('System.Contnrs', 'TObjectQueue', '  FOffen := TObjectQueue.Create;'#10 +
    '  FOffen.Push(Knoten);'#10'  Knoten := TKnoten(FOffen.Pop);'#10);
  mFound := StackFindings(mSource);
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)), mFound[0].Details);
  mFixed := TChangeSignature.ApplyEdits(mSource, mFound[0].Fixes[0].Edits);
  AssertContains(mFixed, '  FOffen := TObjectQueue<TKnoten>.Create(False);'#10'  FOffen.Enqueue(Knoten);'#10 +
    '  Knoten := FOffen.Extract;'#10);
  AssertParses(mFixed);
end;

procedure TLegacyStackQueueTests.NoFixGivesReasonInHover;
var
  mFound: TArray<TRuleFinding>;
begin
  // Ohne Create in der Unit lässt sich die Besitzregel nicht setzen.
  mFound := StackFindings(Suche('System.Contnrs', 'TObjectStack', '  Knoten := TKnoten(FOffen.Pop);'#10));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
  Assert.IsTrue(StartsStr('Keine Schnellkorrektur: ', mFound[0].Details), mFound[0].Details);
  // Verschiedene Casts desselben Stapels.
  mFound := StackFindings(Suche('System.Contnrs', 'TStack', '  FOffen := TStack.Create;'#10 +
    '  Knoten := TKnoten(FOffen.Pop);'#10'  Obj := TObject(FOffen.Pop);'#10));
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
  AssertContains(mFound[0].Details, 'TKnoten');
  // AtLeast gibt es generisch nicht.
  mFound := StackFindings(Suche('System.Contnrs', 'TStack', '  FOffen := TStack.Create;'#10 +
    '  if FOffen.AtLeast(2) then'#10'    Knoten := TKnoten(FOffen.Pop);'#10));
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
  AssertContains(mFound[0].Details, 'AtLeast');
end;

/// <summary>Ordner Tests\Referenzprojekt oberhalb der Testanwendung; '' ohne.</summary>
function ReferenceFolder: string;
var
  mDirectory: string;
begin
  mDirectory := ExtractFileDir(ParamStr(0));
  while mDirectory <> '' do
  begin
    Result := TPath.Combine(mDirectory, TPath.Combine('Tests', 'Referenzprojekt'));
    if TDirectory.Exists(Result) then
    begin
      Exit;
    end;
    if ExtractFileDir(mDirectory) = mDirectory then
    begin
      Break;
    end;
    mDirectory := ExtractFileDir(mDirectory);
  end;
  Result := '';
end;

procedure TLegacyStackQueueTests.ReferenceProjectMatchesMarkers;
const
  cMarker = '// ERWARTET-INDEX: legacy-stack-queue';
var
  mFolder, mFileName, mExpected, mActual: string;
  mFiles: TArray<string>;
  mTexts: TArray<string>;
  mLines: TArray<string>;
  mFileFormat: TFileFormat;
  mIndex: ISymbolIndex;
  mFinding: TRuleFinding;
  mFileIndex, mLineIndex: Integer;
begin
  // Golden-Korpus mit Index (#152, #94): alle Units des Referenzprojekts samt RTL-Stubs; genau die markierten
  // Zeilen, jede weitere Meldung ist ein Fehlalarm.
  mFolder := ReferenceFolder;
  if mFolder = '' then
  begin
    Assert.Pass('Referenzprojekt nicht gefunden; Prüfung übersprungen');
  end;
  mIndex := BaseIndex;
  mFiles := nil;
  mTexts := nil;
  for mFileName in TDirectory.GetFiles(TPath.Combine(mFolder, 'Source'), '*.pas') do
  begin
    mFiles := mFiles + [mFileName];
    mTexts := mTexts + [TFileEncoding.Decode(TFile.ReadAllBytes(mFileName), mFileFormat)];
    mIndex.AddUnit(TIndexExtractor.ExtractText(mTexts[High(mTexts)], mFileName, nil));
  end;
  mExpected := '';
  mActual := '';
  for mFileIndex := 0 to High(mFiles) do
  begin
    mLines := mTexts[mFileIndex].Replace(#13#10, #10).Split([#10]);
    for mLineIndex := 0 to High(mLines) do
    begin
      if mLines[mLineIndex].Contains(cMarker) then
      begin
        mExpected := mExpected + ExtractFileName(mFiles[mFileIndex]) + ':' + IntToStr(mLineIndex + 1) + #10;
      end;
    end;
    for mFinding in TRuleAssert.IndexFindings(TLegacyStackQueueRule.Create, mTexts[mFileIndex], mIndex, cStackQueueOn,
      ExtractFileName(mFiles[mFileIndex])) do
    begin
      mActual := mActual + ExtractFileName(mFiles[mFileIndex]) + ':' + IntToStr(mFinding.Range.StartPos.Line + 1) + #10;
    end;
  end;
  Assert.AreNotEqual('', mExpected, 'Keine Markierungen im Referenzprojekt');
  Assert.AreEqual(mExpected, mActual);
  mFiles := nil;
  mTexts := nil;
  mLines := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TLegacyTListTests);
  TDUnitX.RegisterTestFixture(TLegacyStackQueueTests);

end.
