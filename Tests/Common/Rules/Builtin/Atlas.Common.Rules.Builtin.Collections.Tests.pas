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
  Atlas.Tests.RuleAssert;

const
  RuleOn = '{"rules": {"legacy-tlist": "info"}}';

const
  LagerFile = 'C:\Projekt\Lager.pas';
  AuftraegeFile = 'C:\Projekt\Auftraege.pas';

type
  TProjectFile = record
    Name: string;
    Text: string;
  end;

/// <summary>System, System.Classes, System.Contnrs und System.Generics.Collections als Stubs.</summary>
function BaseIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText('unit System;'#10'interface'#10'type'#10'  TObject = class'#10 +
    '  end;'#10'implementation'#10'end.', 'C:\BDS\source\System.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText('unit System.Classes;'#10'interface'#10'type'#10 +
    '  TList = class(TObject)'#10'  protected'#10'    function Get(Index: Integer): Pointer;'#10 +
    '  public'#10'    function Add(Item: Pointer): Integer;'#10'    function First: Pointer;'#10 +
    '    function Last: Pointer;'#10'    function Extract(Item: Pointer): Pointer;'#10 +
    '    property Count: Integer read FCount;'#10 +
    '    property Items[Index: Integer]: Pointer read Get; default;'#10'  end;'#10 +
    '  TStrings = class(TObject)'#10'  public'#10 +
    '    property Objects[Index: Integer]: TObject read GetObject;'#10'  end;'#10 +
    'implementation'#10'end.', 'C:\BDS\source\System.Classes.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText('unit System.Contnrs;'#10'interface'#10'uses'#10'  System.Classes;'#10 +
    'type'#10'  TObjectList = class(TList)'#10'  protected'#10'    function GetItem(Index: Integer): TObject;'#10 +
    '  public'#10'    function First: TObject;'#10'    function Last: TObject;'#10 +
    '    property Items[Index: Integer]: TObject read GetItem; default;'#10'  end;'#10 +
    '  TOrderedList = class(TObject)'#10'  public'#10'    function Count: Integer;'#10 +
    '    function AtLeast(ACount: Integer): Boolean;'#10 +
    '    function Push(AItem: Pointer): Pointer;'#10'    function Pop: Pointer;'#10'    function Peek: Pointer;'#10 +
    '  end;'#10'  TStack = class(TOrderedList)'#10'  end;'#10'  TQueue = class(TOrderedList)'#10'  end;'#10 +
    '  TObjectStack = class(TStack)'#10'  public'#10'    function Push(AObject: TObject): TObject;'#10 +
    '    function Pop: TObject;'#10'    function Peek: TObject;'#10'  end;'#10 +
    '  TObjectQueue = class(TQueue)'#10'  public'#10'    function Push(AObject: TObject): TObject;'#10 +
    '    function Pop: TObject;'#10'    function Peek: TObject;'#10'  end;'#10 +
    'implementation'#10'end.', 'C:\BDS\source\System.Contnrs.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText('unit System.Generics.Collections;'#10'interface'#10'type'#10 +
    '  TList<T> = class(TObject)'#10'  protected'#10'    function GetItem(Index: Integer): T;'#10'  public'#10 +
    '    function First: T;'#10'    property Items[Index: Integer]: T read GetItem; default;'#10'  end;'#10 +
    '  TObjectList<T: class> = class(TList<T>)'#10'  end;'#10 +
    '  TStack<T> = class(TObject)'#10'  public'#10'    function Pop: T;'#10'    function Peek: T;'#10 +
    '    function Extract: T;'#10'  end;'#10'  TQueue<T> = class(TObject)'#10'  public'#10 +
    '    function Dequeue: T;'#10'    function Peek: T;'#10'    function Extract: T;'#10'  end;'#10 +
    '  TObjectStack<T: class> = class(TStack<T>)'#10'  end;'#10'  TObjectQueue<T: class> = class(TQueue<T>)'#10 +
    '  end;'#10 +
    'implementation'#10'end.', 'C:\BDS\source\System.Generics.Collections.pas', nil));
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
  Result := TRuleAssert.IndexFindings(TLegacyTListRule.Create, ASource, RtlIndex, RuleOn, 'Auftraege.pas');
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
  Texts: TDictionary<string, string>;
  Index: ISymbolIndex;
  Entry: TProjectFile;
  Project: TRuleProject;
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
  Context: TRuleContext;
  Tree: TSyntaxTree;
  Text: string;
  Complete: Boolean;
begin
  Complete := AComplete;
  Texts := TDictionary<string, string>.Create;
  try
    Index := BaseIndex;
    Project := Default(TRuleProject);
    Project.FileName := 'C:\Projekt\App.dproj';
    Project.Kind := TRuleProjectKind.Application;
    for Entry in AFiles do
    begin
      Texts.AddOrSetValue(UpperCase(Entry.Name), Entry.Text);
      Index.AddUnit(TIndexExtractor.ExtractText(Entry.Text, Entry.Name, nil));
      Project.Sources := Project.Sources + [Entry.Name];
    end;
    Settings := TConfigurationParser.Parse(RuleOn, Issues);
    Texts.TryGetValue(UpperCase(ACheck), Text);
    Tree := TSyntaxTreeCache.Parse(Text);
    try
      Context := Default(TRuleContext);
      Context.FileName := ACheck;
      Context.RelativePath := ExtractFileName(ACheck);
      Context.UnitName := ChangeFileExt(ExtractFileName(ACheck), '');
      Context.Text := Text;
      Context.Tree := Tree;
      Context.Index := Index;
      Context.ProjectFiles := TRuleProjectFiles.Create([Project], Index,
        function(const AFileName: string; out AText: string): Boolean
        begin
          Result := Texts.TryGetValue(UpperCase(AFileName), AText);
        end,
        function(out AReason: string): Boolean
        begin
          Result := Complete;
          if not Complete then
            AReason := 'Index läuft (1 von 2 Units)';
        end);
      Result := TRuleEngine.Run([TLegacyTListRule.Create], Settings, Context);
      Context.ProjectFiles := nil;
    finally
      Tree.Free;
    end;
  finally
    Texts.Free;
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
  PublicRegale = '  public'#10'    Regale: TList;'#10;

procedure AssertContains(const AText, APart: string);
begin
  Assert.IsTrue(Pos(APart, AText) > 0, Format('"%s" fehlt in:'#10'%s', [APart, AText]));
end;

procedure TLegacyTListTests.IssueExample;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(Auftrag('System.Classes', 'TList', '  Pos := TPosition(FPositionen[I]);'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Ungenerische TList mit Cast beim Lesen; TList<TPosition> prüft den Typ beim Übersetzen.',
    Found[0].Message);
  // An der Deklaration des Felds.
  Assert.AreEqual(9, Found[0].Range.StartPos.Line);
  Assert.AreEqual(4, Found[0].Range.StartPos.Character);
  // Schnellkorrektur (#1105).
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('In TList<TPosition> umwandeln', Found[0].Fixes[0].Title);
  // Mit System.Generics.Collections hinter System.Classes bleibt TList die ungenerische Klasse.
  Assert.AreEqual(1, Integer(Length(Findings(Auftrag('System.Classes, System.Generics.Collections', 'TList',
    '  Pos := TPosition(FPositionen[I]);'#10)))));
  // Die korrigierte Form ist still.
  Assert.AreEqual(0, Integer(Length(Findings(Auftrag('System.Classes, System.Generics.Collections',
    'TList<TPosition>', '  Pos := FPositionen[I];'#10)))));
end;

procedure TLegacyTListTests.ReadForms;
var
  Statement: string;
  Found: TArray<TRuleFinding>;
  Index: ISymbolIndex;
begin
  for Statement in ['  Pos := TPosition(FPositionen.Items[I]);'#10, '  Pos := TPosition(FPositionen.First);'#10,
    '  Pos := TPosition(FPositionen.Last());'#10, '  Pos := TPosition(Self.FPositionen[I]);'#10,
    '  Pos := FPositionen[I] as TPosition;'#10, '  Pos := (FPositionen[I]) as TPosition;'#10,
    '  if TPosition(FPositionen[0]) = nil then'#10'    Exit;'#10,
    '  Pos := TPosition(FPositionen.Extract(Pos));'#10] do
  begin
    Found := Findings(Auftrag('System.Classes', 'TList', Statement));
    Assert.AreEqual(1, Integer(Length(Found)), Statement);
    Assert.AreEqual(9, Found[0].Range.StartPos.Line, Statement);
  end;
  // Mehrere Casts derselben Liste: ein Treffer.
  Found := Findings(Auftrag('System.Classes', 'TList', '  Pos := TPosition(FPositionen[0]);'#10 +
    '  Pos := TPosition(FPositionen.Last);'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  // RTL-Quellen ohne Namespace (Classes statt System.Classes).
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText('unit Classes;'#10'interface'#10'type'#10'  TList = class'#10 +
    '  public'#10'    function Get(Index: Integer): Pointer;'#10 +
    '    property Items[Index: Integer]: Pointer read Get; default;'#10'  end;'#10'implementation'#10'end.',
    'C:\Alt\Classes.pas', nil));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.IndexFindings(TLegacyTListRule.Create,
    Auftrag('Classes', 'TList', '  Pos := TPosition(FPositionen[I]);'#10), Index, RuleOn, 'Auftraege.pas'))));
end;

procedure TLegacyTListTests.ObjectListLocalsAndParameters;
var
  Source: string;
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(Auftrag('System.Classes, System.Contnrs', 'TObjectList',
    '  Pos := TPosition(FPositionen[I]);'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Ungenerische TObjectList mit Cast beim Lesen; TObjectList<TPosition> prüft den Typ beim ' +
    'Übersetzen.', Found[0].Message);
  // Lokale Variable und Parameter: je Deklaration ein Treffer an ihrem Namen.
  Source := 'unit Auftraege;'#10'interface'#10'uses'#10'  System.Classes;'#10'type'#10'  TPosition = class'#10 +
    '  end;'#10'implementation'#10'procedure Lesen(Quelle: TList);'#10'var'#10'  Ziel: TList;'#10 +
    '  Pos: TPosition;'#10'begin'#10'  Pos := TPosition(Quelle[0]);'#10'  Pos := TPosition(Ziel.First);'#10 +
    'end;'#10'end.';
  Found := Findings(Source);
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual(8, Found[0].Range.StartPos.Line);
  Assert.AreEqual(16, Found[0].Range.StartPos.Character);
  Assert.AreEqual(10, Found[1].Range.StartPos.Line);
  Assert.AreEqual(2, Found[1].Range.StartPos.Character);
end;

procedure TLegacyTListTests.SeveralCastTypes;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(Auftrag('System.Classes', 'TList', '  Pos := TPosition(FPositionen[0]);'#10 +
    '  Obj := TObject(FPositionen[1]);'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Ungenerische TList mit Casts auf TPosition, TObject beim Lesen; eine generische Liste prüft den ' +
    'Typ beim Übersetzen.', Found[0].Message);
end;

procedure TLegacyTListTests.DeclaredInOtherUnit;
var
  Source: string;
  Found: TArray<TRuleFinding>;
begin
  // Das Feld steht in Lager: der Treffer sitzt am Cast dieser Datei.
  Source := 'unit Auftraege;'#10'interface'#10'uses'#10'  System.Classes, Lager;'#10'type'#10 +
    '  TPosition = class'#10'  end;'#10'implementation'#10'procedure Lesen(L: TLager);'#10'var'#10 +
    '  Pos: TPosition;'#10'begin'#10'  Pos := TPosition(L.Regale[0]);'#10'end;'#10'end.';
  Found := Findings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(12, Found[0].Range.StartPos.Line);
  Assert.AreEqual(9, Found[0].Range.StartPos.Character);
  Assert.AreEqual(12, Found[0].Range.EndPos.Line);
  Assert.AreEqual(31, Found[0].Range.EndPos.Character);
end;

procedure TLegacyTListTests.SilentCases;
var
  Statement: string;
begin
  for Statement in [
    // Ohne Cast, Pointer, Funktionsaufruf statt Cast, unbekannter Typ.
    '  I := FPositionen.Count;'#10'  FPositionen.Add(Pos);'#10, '  Obj := Pointer(FPositionen[I]);'#10,
    '  Pos := Umwandeln(FPositionen[I]);'#10, '  Pos := TUnbekannt(FPositionen[I]);'#10,
    // Cast auf etwas anderes als die Liste.
    '  Pos := TPosition(Obj);'#10] do
    Assert.AreEqual(0, Integer(Length(Findings(Auftrag('System.Classes', 'TList', Statement).Replace('begin'#10,
      'function Umwandeln(P: Pointer): TPosition;'#10'begin'#10'end;'#10#10'begin'#10)))), Statement);
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
    Auftrag('System.Classes', 'TList', '  Pos := TPosition(FPositionen[I]);'#10), nil, RuleOn, 'Auftraege.pas'))));
end;

procedure TLegacyTListTests.Settings;
var
  Source: string;
begin
  Source := Auftrag('System.Classes', 'TList', '  Pos := TPosition(FPositionen[I]);'#10);
  // Standard aus.
  Assert.AreEqual(0, Integer(Length(Findings(Source, '', 'Source/Auftraege.pas'))));
  Assert.AreEqual(1, Integer(Length(Findings(Source, RuleOn, 'Source/Auftraege.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"legacy-tlist": "off"}}', 'Source/Auftraege.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source,
    '{"rules": {"legacy-tlist": {"severity": "info", "exclude": ["Source/*.pas"]}}}', 'Source/Auftraege.pas'))));
  Assert.AreEqual(1, Integer(Length(Findings(Source,
    '{"rules": {"legacy-tlist": {"severity": "info", "exclude": ["Alt/*.pas"]}}}', 'Source/Auftraege.pas'))));
end;

procedure TLegacyTListTests.FixConvertsTheList;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Auftrag('System.Classes', 'TList', '  FPositionen := TList.Create;'#10 +
    '  Pos := TPosition(FPositionen[I]);'#10'  Pos := FPositionen.First as TPosition;'#10);
  Found := Findings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('', Found[0].Details);
  // Nur diese Datei, alle Typen bekannt: auch für source.fixAll.
  Assert.IsTrue(Found[0].Fixes[0].Safe);
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes[0].OtherFiles)));
  Fixed := TChangeSignature.ApplyEdits(Source, Found[0].Fixes[0].Edits);
  AssertContains(Fixed, '  System.Classes,'#10'  System.Generics.Collections;'#10);
  AssertContains(Fixed, '    FPositionen: TList<TPosition>;'#10);
  AssertContains(Fixed, '  FPositionen := TList<TPosition>.Create;'#10);
  AssertContains(Fixed, '  Pos := FPositionen[I];'#10'  Pos := FPositionen.First;'#10);
  // Das Ergebnis meldet die Regel nicht mehr.
  Assert.AreEqual(0, Integer(Length(Findings(Fixed))));
end;

procedure TLegacyTListTests.NoFixGivesReasonInHover;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(Auftrag('System.Classes', 'TList', '  FPositionen.Sort(Vergleichen);'#10 +
    '  Pos := TPosition(FPositionen[I]);'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
  Assert.IsTrue(StartsStr('Keine Schnellkorrektur: ', Found[0].Details), Found[0].Details);
  AssertContains(Found[0].Details, 'TListSortCompare');
  // Verschiedene Casts derselben Liste.
  Found := Findings(Auftrag('System.Classes', 'TList', '  Pos := TPosition(FPositionen[0]);'#10 +
    '  Obj := TObject(FPositionen[1]);'#10));
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
  AssertContains(Found[0].Details, 'TPosition');
end;

procedure TLegacyTListTests.FixInDeclaringUnitOfOtherUnit;
var
  Files: TArray<TProjectFile>;
  Found: TArray<TRuleFinding>;
  Fix: TRuleFix;
begin
  // Das öffentliche Feld wird in Auftraege gelesen: beide Units ändern sich, also nicht Safe.
  Files := [ProjectFile(LagerFile, LagerText(PublicRegale)), ProjectFile(AuftraegeFile, AuftraegeText(''))];
  Found := ProjectFindings(Files, LagerFile, True);
  Assert.AreEqual(0, Integer(Length(Found)), 'Lager selbst liest nicht mit Cast');
  Found := ProjectFindings(Files, AuftraegeFile, True);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)), Found[0].Details);
  Fix := Found[0].Fixes[0];
  Assert.AreEqual('In TList<TRegal> umwandeln', Fix.Title);
  Assert.IsFalse(Fix.Safe);
  AssertContains(TChangeSignature.ApplyEdits(Files[1].Text, Fix.Edits), '  R := L.Regale[0];'#10);
  Assert.AreEqual(1, Integer(Length(Fix.OtherFiles)));
  Assert.AreEqual(LagerFile, Fix.OtherFiles[0].FileName);
  AssertContains(TChangeSignature.ApplyEdits(Files[0].Text, Fix.OtherFiles[0].Edits),
    '  System.Classes,'#10'  System.Generics.Collections;'#10);
  AssertContains(TChangeSignature.ApplyEdits(Files[0].Text, Fix.OtherFiles[0].Edits),
    '    Regale: TList<TRegal>;'#10);
  AssertContains(TChangeSignature.ApplyEdits(Files[0].Text, Fix.OtherFiles[0].Edits),
    '  Regale := TList<TRegal>.Create;'#10);
end;

procedure TLegacyTListTests.FixFromUnitWithTheCast;
var
  Files: TArray<TProjectFile>;
  Found: TArray<TRuleFinding>;
begin
  // Eine weitere Unit nutzt Sort: keine Korrektur, der Grund nennt es.
  Files := [ProjectFile(LagerFile, LagerText(PublicRegale)),
    ProjectFile(AuftraegeFile, AuftraegeText('  L.Regale.Sort(Vergleichen);'#10))];
  Found := ProjectFindings(Files, AuftraegeFile, True);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
  AssertContains(Found[0].Details, 'TListSortCompare');
  // Projekt noch nicht fertig geladen.
  Files := [ProjectFile(LagerFile, LagerText(PublicRegale)), ProjectFile(AuftraegeFile, AuftraegeText(''))];
  Found := ProjectFindings(Files, AuftraegeFile, False);
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
  AssertContains(Found[0].Details, 'Index läuft');
end;

procedure TLegacyTListTests.PropertyLeadsToField;
var
  Files: TArray<TProjectFile>;
  Found: TArray<TRuleFinding>;
  Fixed: string;
begin
  // L.Regale ist eine Property, die das private Feld liest: umgewandelt werden Feld und Property.
  Files := [ProjectFile(LagerFile, LagerText('  private'#10'    FRegale: TList;'#10'  public'#10 +
    '    property Regale: TList read FRegale;'#10).Replace('  Regale := TList.Create;', '  FRegale := TList.Create;')),
    ProjectFile(AuftraegeFile, AuftraegeText(''))];
  Found := ProjectFindings(Files, AuftraegeFile, True);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)), Found[0].Details);
  Fixed := TChangeSignature.ApplyEdits(Files[0].Text, Found[0].Fixes[0].OtherFiles[0].Edits);
  AssertContains(Fixed, '    FRegale: TList<TRegal>;'#10);
  AssertContains(Fixed, '    property Regale: TList<TRegal> read FRegale;'#10);
  AssertContains(Fixed, '  FRegale := TList<TRegal>.Create;'#10);
end;

procedure TLegacyTListTests.OtherUnitsWithoutProject;
var
  Found: TArray<TRuleFinding>;
begin
  // Ohne Projekt (Linter): Die Deklaration in Lager lässt sich nicht ändern, der Grund steht im Hover.
  Found := Findings('unit Auftraege;'#10'interface'#10'uses'#10'  System.Classes, Lager;'#10'type'#10 +
    '  TPosition = class'#10'  end;'#10'implementation'#10'procedure Lesen(L: TLager);'#10'var'#10 +
    '  Pos: TPosition;'#10'begin'#10'  Pos := TPosition(L.Regale[0]);'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
  AssertContains(Found[0].Details, 'ohne geladenes Projekt');
  // Öffentliches Feld dieser Unit: andere Units sind ohne Projekt nicht prüfbar.
  Found := Findings(Auftrag('System.Classes', 'TList', '  Pos := TPosition(FPositionen[I]);'#10).Replace(
    '  private'#10'    FPositionen', '  public'#10'    FPositionen'));
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
  AssertContains(Found[0].Details, 'in anderen Units sichtbar');
end;

{ TLegacyStackQueueTests }

const
  StackQueueOn = '{"rules": {"legacy-stack-queue": "info"}}';

function StackFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TLegacyStackQueueRule.Create, ASource, RtlIndex, StackQueueOn, 'Suche.pas');
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
  Found: TArray<TRuleFinding>;
begin
  Found := StackFindings(Suche('System.Contnrs', 'TObjectStack', '  Knoten := TKnoten(FOffen.Pop);'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Ungenerischer TObjectStack mit Cast beim Lesen; TObjectStack<TKnoten> prüft den Typ beim ' +
    'Übersetzen.', Found[0].Message);
  // An der Deklaration des Felds.
  Assert.AreEqual(9, Found[0].Range.StartPos.Line);
  Assert.AreEqual(4, Found[0].Range.StartPos.Character);
  // System.Generics.Collections hinter System.Contnrs: TObjectStack bleibt die ungenerische Klasse.
  Assert.AreEqual(1, Integer(Length(StackFindings(Suche('System.Contnrs, System.Generics.Collections',
    'TObjectStack', '  Knoten := TKnoten(FOffen.Pop);'#10)))));
  // Die korrigierte Form ist still.
  Assert.AreEqual(0, Integer(Length(StackFindings(Suche('System.Contnrs, System.Generics.Collections',
    'TObjectStack<TKnoten>', '  Knoten := FOffen.Pop;'#10)))));
end;

procedure TLegacyStackQueueTests.ReadForms;
var
  Statement: string;
  Found: TArray<TRuleFinding>;
begin
  for Statement in ['  Knoten := TKnoten(FOffen.Peek);'#10, '  Knoten := TKnoten(FOffen.Pop());'#10,
    '  Knoten := TKnoten(Self.FOffen.Pop);'#10, '  Knoten := FOffen.Pop as TKnoten;'#10,
    '  Knoten := (FOffen.Peek) as TKnoten;'#10, '  if TKnoten(FOffen.Peek) = nil then'#10'    Exit;'#10] do
  begin
    Found := StackFindings(Suche('System.Contnrs', 'TObjectStack', Statement));
    Assert.AreEqual(1, Integer(Length(Found)), Statement);
    Assert.AreEqual(9, Found[0].Range.StartPos.Line, Statement);
  end;
  // Mehrere Casts desselben Stapels: ein Treffer.
  Found := StackFindings(Suche('System.Contnrs', 'TObjectStack', '  Knoten := TKnoten(FOffen.Peek);'#10 +
    '  Knoten := TKnoten(FOffen.Pop);'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
end;

procedure TLegacyStackQueueTests.StacksAndQueues;
var
  Found: TArray<TRuleFinding>;
begin
  Found := StackFindings(Suche('System.Contnrs', 'TStack', '  Knoten := TKnoten(FOffen.Pop);'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Ungenerischer TStack mit Cast beim Lesen; TStack<TKnoten> prüft den Typ beim Übersetzen.',
    Found[0].Message);
  Found := StackFindings(Suche('System.Contnrs', 'TQueue', '  Knoten := TKnoten(FOffen.Pop);'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Ungenerische TQueue mit Cast beim Lesen; TQueue<TKnoten> prüft den Typ beim Übersetzen.',
    Found[0].Message);
  Found := StackFindings(Suche('System.Contnrs', 'TObjectQueue', '  Knoten := TKnoten(FOffen.Peek);'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Ungenerische TObjectQueue mit Cast beim Lesen; TObjectQueue<TKnoten> prüft den Typ beim ' +
    'Übersetzen.', Found[0].Message);
  // RTL-Quellen ohne Namespace (Contnrs statt System.Contnrs).
  Assert.AreEqual(1, Integer(Length(TRuleAssert.IndexFindings(TLegacyStackQueueRule.Create,
    Suche('Contnrs', 'TObjectStack', '  Knoten := TKnoten(FOffen.Pop);'#10), OldRtlIndex, StackQueueOn,
    'Suche.pas'))));
end;

procedure TLegacyStackQueueTests.SeveralCastTypes;
var
  Found: TArray<TRuleFinding>;
begin
  Found := StackFindings(Suche('System.Contnrs', 'TObjectStack', '  Knoten := TKnoten(FOffen.Pop);'#10 +
    '  Obj := TObject(FOffen.Pop);'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Ungenerischer TObjectStack mit Casts auf TKnoten, TObject beim Lesen; ein generischer Stapel ' +
    'prüft den Typ beim Übersetzen.', Found[0].Message);
  Found := StackFindings(Suche('System.Contnrs', 'TQueue', '  Knoten := TKnoten(FOffen.Pop);'#10 +
    '  Obj := TObject(FOffen.Peek);'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Ungenerische TQueue mit Casts auf TKnoten, TObject beim Lesen; eine generische Warteschlange ' +
    'prüft den Typ beim Übersetzen.', Found[0].Message);
end;

procedure TLegacyStackQueueTests.LocalsAndOtherUnits;
var
  Source: string;
  Found: TArray<TRuleFinding>;
  Index: ISymbolIndex;
begin
  // Lokale Variable und Parameter: je Deklaration ein Treffer an ihrem Namen.
  Source := 'unit Suche;'#10'interface'#10'uses'#10'  System.Contnrs;'#10'type'#10'  TKnoten = class'#10 +
    '  end;'#10'implementation'#10'procedure Lesen(Quelle: TObjectQueue);'#10'var'#10'  Ziel: TStack;'#10 +
    '  Knoten: TKnoten;'#10'begin'#10'  Knoten := TKnoten(Quelle.Pop);'#10'  Knoten := TKnoten(Ziel.Peek);'#10 +
    'end;'#10'end.';
  Found := StackFindings(Source);
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual(8, Found[0].Range.StartPos.Line);
  Assert.AreEqual(16, Found[0].Range.StartPos.Character);
  Assert.AreEqual(10, Found[1].Range.StartPos.Line);
  Assert.AreEqual(2, Found[1].Range.StartPos.Character);
  // Das Feld steht in einer anderen Unit: der Treffer sitzt am Cast dieser Datei.
  Index := RtlIndex;
  Index.AddUnit(TIndexExtractor.ExtractText('unit Ablage;'#10'interface'#10'uses'#10'  System.Contnrs;'#10 +
    'type'#10'  TAblage = class'#10'  public'#10'    Stapel: TObjectStack;'#10'  end;'#10'implementation'#10'end.',
    'C:\Projekt\Ablage.pas', nil));
  Source := 'unit Suche;'#10'interface'#10'uses'#10'  System.Contnrs, Ablage;'#10'type'#10'  TKnoten = class'#10 +
    '  end;'#10'implementation'#10'procedure Lesen(A: TAblage);'#10'var'#10'  Knoten: TKnoten;'#10'begin'#10 +
    '  Knoten := TKnoten(A.Stapel.Pop);'#10'end;'#10'end.';
  Found := TRuleAssert.IndexFindings(TLegacyStackQueueRule.Create, Source, Index, StackQueueOn, 'Suche.pas');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(12, Found[0].Range.StartPos.Line);
  Assert.AreEqual(12, Found[0].Range.StartPos.Character);
end;

procedure TLegacyStackQueueTests.SilentCases;
var
  Statement: string;
begin
  for Statement in [
    // Ohne Cast, Pointer, unbekannter Typ, Cast auf etwas anderes als den Stapel.
    '  FOffen.Push(Knoten);'#10'  if FOffen.Count = 0 then'#10'    Exit;'#10'  FOffen.Pop;'#10,
    '  Obj := Pointer(FOffen.Pop);'#10, '  Knoten := TUnbekannt(FOffen.Pop);'#10, '  Knoten := TKnoten(Obj);'#10] do
    Assert.AreEqual(0, Integer(Length(StackFindings(Suche('System.Contnrs', 'TObjectStack', Statement)))), Statement);
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
    Suche('System.Contnrs', 'TObjectStack', '  Knoten := TKnoten(FOffen.Pop);'#10), nil, StackQueueOn,
    'Suche.pas'))));
end;

procedure TLegacyStackQueueTests.Settings;
var
  Source: string;
begin
  Source := Suche('System.Contnrs', 'TObjectStack', '  Knoten := TKnoten(FOffen.Pop);'#10);
  // Standard aus.
  Assert.AreEqual(0, Integer(Length(StackFindings(Source, '', 'Source/Suche.pas'))));
  Assert.AreEqual(1, Integer(Length(StackFindings(Source, StackQueueOn, 'Source/Suche.pas'))));
  Assert.AreEqual(0, Integer(Length(StackFindings(Source, '{"rules": {"legacy-stack-queue": "off"}}',
    'Source/Suche.pas'))));
  Assert.AreEqual(0, Integer(Length(StackFindings(Source,
    '{"rules": {"legacy-stack-queue": {"severity": "info", "exclude": ["Source/*.pas"]}}}', 'Source/Suche.pas'))));
  Assert.AreEqual(1, Integer(Length(StackFindings(Source,
    '{"rules": {"legacy-stack-queue": {"severity": "info", "exclude": ["Alt/*.pas"]}}}', 'Source/Suche.pas'))));
end;

procedure AssertParses(const AText: string);
var
  Tree: TSyntaxTree;
begin
  Tree := TSyntaxTreeCache.Parse(AText);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)), AText);
  finally
    Tree.Free;
  end;
end;

procedure TLegacyStackQueueTests.FixObjectStack;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  // Das Beispiel aus #1106 mit Create: TObjectStack<T> besitzt seine Objekte, daher Create(False). Pop ist bei
  // TObjectStack<T> eine Prozedur, die das Objekt freigibt; das Element ohne Freigabe liefert Extract.
  Source := Suche('System.Contnrs', 'TObjectStack', '  FOffen := TObjectStack.Create;'#10 +
    '  FOffen.Push(Knoten);'#10'  Knoten := TKnoten(FOffen.Pop);'#10'  Knoten := FOffen.Peek as TKnoten;'#10);
  Found := StackFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)), Found[0].Details);
  Assert.AreEqual('In TObjectStack<TKnoten> umwandeln', Found[0].Fixes[0].Title);
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes[0].OtherFiles)));
  Fixed := TChangeSignature.ApplyEdits(Source, Found[0].Fixes[0].Edits);
  // System.Contnrs wird nicht mehr gebraucht.
  AssertContains(Fixed, 'uses'#10'  System.Generics.Collections;'#10);
  AssertContains(Fixed, '    FOffen: TObjectStack<TKnoten>;'#10);
  AssertContains(Fixed, '  FOffen := TObjectStack<TKnoten>.Create(False);'#10);
  AssertContains(Fixed, '  FOffen.Push(Knoten);'#10'  Knoten := FOffen.Extract;'#10'  Knoten := FOffen.Peek;'#10);
  AssertParses(Fixed);
  // Das Ergebnis meldet die Regel nicht mehr.
  Assert.AreEqual(0, Integer(Length(StackFindings(Fixed))));
  // TStack besitzt nichts: Create bleibt, Pop bleibt.
  Source := Suche('System.Contnrs', 'TStack', '  FOffen := TStack.Create;'#10 +
    '  Knoten := TKnoten(FOffen.Pop);'#10);
  Found := StackFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)), Found[0].Details);
  Fixed := TChangeSignature.ApplyEdits(Source, Found[0].Fixes[0].Edits);
  AssertContains(Fixed, '  FOffen := TStack<TKnoten>.Create;'#10'  Knoten := FOffen.Pop;'#10);
  AssertParses(Fixed);
end;

procedure TLegacyStackQueueTests.FixQueueRenamesMethods;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  // TQueue<T> heißt Enqueue/Dequeue statt Push/Pop.
  Source := Suche('System.Contnrs', 'TQueue', '  FOffen := TQueue.Create;'#10'  FOffen.Push(Knoten);'#10 +
    '  Knoten := TKnoten(FOffen.Pop);'#10);
  Found := StackFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)), Found[0].Details);
  Assert.AreEqual('In TQueue<TKnoten> umwandeln', Found[0].Fixes[0].Title);
  Fixed := TChangeSignature.ApplyEdits(Source, Found[0].Fixes[0].Edits);
  AssertContains(Fixed, '    FOffen: TQueue<TKnoten>;'#10);
  AssertContains(Fixed, '  FOffen := TQueue<TKnoten>.Create;'#10'  FOffen.Enqueue(Knoten);'#10 +
    '  Knoten := FOffen.Dequeue;'#10);
  AssertParses(Fixed);
  // TObjectQueue: Create(False), Enqueue und Extract.
  Source := Suche('System.Contnrs', 'TObjectQueue', '  FOffen := TObjectQueue.Create;'#10 +
    '  FOffen.Push(Knoten);'#10'  Knoten := TKnoten(FOffen.Pop);'#10);
  Found := StackFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)), Found[0].Details);
  Fixed := TChangeSignature.ApplyEdits(Source, Found[0].Fixes[0].Edits);
  AssertContains(Fixed, '  FOffen := TObjectQueue<TKnoten>.Create(False);'#10'  FOffen.Enqueue(Knoten);'#10 +
    '  Knoten := FOffen.Extract;'#10);
  AssertParses(Fixed);
end;

procedure TLegacyStackQueueTests.NoFixGivesReasonInHover;
var
  Found: TArray<TRuleFinding>;
begin
  // Ohne Create in der Unit lässt sich die Besitzregel nicht setzen.
  Found := StackFindings(Suche('System.Contnrs', 'TObjectStack', '  Knoten := TKnoten(FOffen.Pop);'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
  Assert.IsTrue(StartsStr('Keine Schnellkorrektur: ', Found[0].Details), Found[0].Details);
  // Verschiedene Casts desselben Stapels.
  Found := StackFindings(Suche('System.Contnrs', 'TStack', '  FOffen := TStack.Create;'#10 +
    '  Knoten := TKnoten(FOffen.Pop);'#10'  Obj := TObject(FOffen.Pop);'#10));
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
  AssertContains(Found[0].Details, 'TKnoten');
  // AtLeast gibt es generisch nicht.
  Found := StackFindings(Suche('System.Contnrs', 'TStack', '  FOffen := TStack.Create;'#10 +
    '  if FOffen.AtLeast(2) then'#10'    Knoten := TKnoten(FOffen.Pop);'#10));
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
  AssertContains(Found[0].Details, 'AtLeast');
end;

/// <summary>Ordner Tests\Referenzprojekt oberhalb der Testanwendung; '' ohne.</summary>
function ReferenceFolder: string;
var
  Directory: string;
begin
  Directory := ExtractFileDir(ParamStr(0));
  while Directory <> '' do
  begin
    Result := TPath.Combine(Directory, TPath.Combine('Tests', 'Referenzprojekt'));
    if TDirectory.Exists(Result) then
      Exit;
    if ExtractFileDir(Directory) = Directory then
      Break;
    Directory := ExtractFileDir(Directory);
  end;
  Result := '';
end;

procedure TLegacyStackQueueTests.ReferenceProjectMatchesMarkers;
const
  Marker = '// ERWARTET-INDEX: legacy-stack-queue';
var
  Folder, FileName, Expected, Actual: string;
  Files: TArray<string>;
  Texts: TArray<string>;
  Lines: TArray<string>;
  FileFormat: TFileFormat;
  Index: ISymbolIndex;
  Finding: TRuleFinding;
  FileIndex, LineIndex: Integer;
begin
  // Golden-Korpus mit Index (#152, #94): alle Units des Referenzprojekts samt RTL-Stubs; genau die markierten
  // Zeilen, jede weitere Meldung ist ein Fehlalarm.
  Folder := ReferenceFolder;
  if Folder = '' then
    Assert.Pass('Referenzprojekt nicht gefunden; Prüfung übersprungen');
  Index := BaseIndex;
  Files := nil;
  Texts := nil;
  for FileName in TDirectory.GetFiles(TPath.Combine(Folder, 'Source'), '*.pas') do
  begin
    Files := Files + [FileName];
    Texts := Texts + [TFileEncoding.Decode(TFile.ReadAllBytes(FileName), FileFormat)];
    Index.AddUnit(TIndexExtractor.ExtractText(Texts[High(Texts)], FileName, nil));
  end;
  Expected := '';
  Actual := '';
  for FileIndex := 0 to High(Files) do
  begin
    Lines := Texts[FileIndex].Replace(#13#10, #10).Split([#10]);
    for LineIndex := 0 to High(Lines) do
      if Lines[LineIndex].Contains(Marker) then
        Expected := Expected + ExtractFileName(Files[FileIndex]) + ':' + IntToStr(LineIndex + 1) + #10;
    for Finding in TRuleAssert.IndexFindings(TLegacyStackQueueRule.Create, Texts[FileIndex], Index, StackQueueOn,
      ExtractFileName(Files[FileIndex])) do
      Actual := Actual + ExtractFileName(Files[FileIndex]) + ':' + IntToStr(Finding.Range.StartPos.Line + 1) + #10;
  end;
  Assert.IsTrue(Expected <> '', 'Keine Markierungen im Referenzprojekt');
  Assert.AreEqual(Expected, Actual);
  Files := nil;
  Texts := nil;
  Lines := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TLegacyTListTests);
  TDUnitX.RegisterTestFixture(TLegacyStackQueueTests);

end.
