unit Atlas.Common.Lsp.UnitSearch.Tests;

// Tests für die Daten des Fensters „Units suchen“ (#777): Art der Unit,
// Herkunft, Kopfkommentar, Git-Zustand, Formularskizze und „Verwendet von“.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.UnitSearch;

type
  [TestFixture]
  TUnitSearchTests = class
  private
    function Context: TUnitSearchContext;
  public
    [Test]
    procedure KindFollowsAncestorChain;
    [Test]
    procedure KindOfTestsAndFallbacks;
    [Test]
    procedure HeaderCommentWithoutMarkers;
    [Test]
    procedure CountsLines;
    [Test]
    procedure GitStates;
    [Test]
    procedure SketchHandlesAlignAndNesting;
    [Test]
    procedure UsedByListsProjectUnits;
    [Test]
    procedure UnitsCarryOriginKindAndProjects;
    [Test]
    procedure PreviewWithoutOpening;
    [Test]
    procedure AddUsesBuildsWorkspaceEdit;
  end;

implementation

uses
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Editing.UsesActions;

function MakeUnit(const AName, AFile: string; const AUses: TArray<string>; const AClass: string = '';
  const AAncestor: string = ''): TUnitIndex;
var
  Symbol: TIndexSymbol;
begin
  Result := Default(TUnitIndex);
  Result.UnitName := AName;
  Result.FileName := AFile;
  Result.InterfaceUses := AUses;
  if AClass <> '' then
  begin
    Symbol := Default(TIndexSymbol);
    Symbol.Name := AClass;
    Symbol.Kind := TIndexSymbolKind.ClassType;
    Symbol.InInterface := True;
    Symbol.Ancestors := [AAncestor];
    Result.Symbols := [Symbol];
  end;
end;

function Chain(const AType: string): TArray<string>;
begin
  Result := nil;
  if SameText(AType, 'TBasisForm') then
    Result := ['Vcl.Forms.TForm']
  else if SameText(AType, 'TKreis') then
    Result := ['TKreis'];
end;

const
  FormText =
    'object Haupt: THaupt'#13#10 +
    '  Caption = ''Kunden'''#13#10 +
    '  ClientWidth = 400'#13#10 +
    '  ClientHeight = 300'#13#10 +
    '  object Kopf: TPanel'#13#10 +
    '    Align = alTop'#13#10 +
    '    Height = 40'#13#10 +
    '    object Titel: TLabel'#13#10 +
    '      Left = 8'#13#10 +
    '      Top = 4'#13#10 +
    '      Width = 50'#13#10 +
    '      Height = 15'#13#10 +
    '      Caption = ''Titel'''#13#10 +
    '    end'#13#10 +
    '  end'#13#10 +
    '  object Liste: TListBox'#13#10 +
    '    Align = alClient'#13#10 +
    '  end'#13#10 +
    '  object Uhr: TTimer'#13#10 +
    '  end'#13#10 +
    'end';

function TUnitSearchTests.Context: TUnitSearchContext;
var
  Main, Tests: TUnitSearchProject;
  Kunden, Haupt, KundenTests, Hilfe, Sys: TUnitIndex;
begin
  Kunden := MakeUnit('Kunden', 'C:\P\Kunden.pas', ['System.SysUtils']);
  Kunden.Includes := ['C:\P\Optionen.inc'];
  Haupt := MakeUnit('Haupt', 'C:\P\Haupt.pas', ['Kunden'], 'THaupt', 'TBasisForm');
  KundenTests := MakeUnit('Kunden.Tests', 'C:\P\Tests\Kunden.Tests.pas', ['DUnitX.TestFramework', 'Kunden']);
  Hilfe := MakeUnit('Hilfe', 'C:\Lib\Hilfe.pas', nil);
  Sys := MakeUnit('System.SysUtils', 'C:\BDS\SysUtils.pas', nil);
  Sys.Library_ := True;
  Main := Default(TUnitSearchProject);
  Main.Name := 'App';
  Main.FileName := 'C:\P\App.dproj';
  Main.Files := ['C:\P\App.dpr', 'C:\P\Kunden.pas', 'C:\P\Haupt.pas', 'C:\P\Neu.pas'];
  Tests := Default(TUnitSearchProject);
  Tests.Name := 'Tests';
  Tests.FileName := 'C:\P\Tests\Tests.dproj';
  Tests.IsTest := True;
  Tests.Files := ['C:\P\Tests\Tests.dpr', 'C:\P\Tests\Kunden.Tests.pas', 'C:\P\Kunden.pas'];
  Result := Default(TUnitSearchContext);
  Result.Units := [Kunden, Haupt, KundenTests, Hilfe, Sys];
  Result.Projects := [Main, Tests];
  Result.AncestorsOf :=
    function(AType: string): TArray<string>
    begin
      Result := Chain(AType);
    end;
  Result.Exists :=
    function(AFile: string): Boolean
    begin
      Result := SameText(AFile, 'C:\P\Haupt.dfm');
    end;
  Result.ReadText :=
    function(AFile: string): string
    begin
      if SameText(AFile, 'C:\P\Haupt.dfm') then
        Result := FormText
      else if SameText(AFile, 'C:\P\Haupt.pas') then
        Result := '// Hauptfenster'#13#10'// der Anwendung'#13#10'unit Haupt;'#13#10'interface'#13#10'end.'
      else
        Result := '';
    end;
  Result.Modified :=
    function(AFile: string): TDateTime
    begin
      Result := EncodeDate(2026, 10, 15);
    end;
  Result.GitState :=
    function(AFile: string): string
    begin
      Result := 'modified';
    end;
end;

procedure TUnitSearchTests.KindFollowsAncestorChain;
var
  Ancestors: TFunc<string, TArray<string>>;
begin
  Ancestors :=
    function(AType: string): TArray<string>
    begin
      Result := Chain(AType);
    end;
  Assert.AreEqual('form', TUnitSearch.KindOf(MakeUnit('A', 'a.pas', nil, 'TA', 'TBasisForm'), Ancestors, False, False));
  Assert.AreEqual('frame', TUnitSearch.KindOf(MakeUnit('A', 'a.pas', nil, 'TA', 'TFrame'), Ancestors, True, False));
  Assert.AreEqual('dm', TUnitSearch.KindOf(MakeUnit('A', 'a.pas', nil, 'TA', 'TDataModule'), Ancestors, True, False));
  // Zyklus in der Kette bricht ab.
  Assert.AreEqual('unit', TUnitSearch.KindOf(MakeUnit('A', 'a.pas', nil, 'TA', 'TKreis'), Ancestors, False, False));
end;

procedure TUnitSearchTests.KindOfTestsAndFallbacks;
begin
  Assert.AreEqual('test', TUnitSearch.KindOf(MakeUnit('A.Tests', 'a.pas', ['DUnitX.TestFramework']), nil, False, False));
  Assert.AreEqual('test', TUnitSearch.KindOf(MakeUnit('A.Tests', 'a.pas', ['TestFramework']), nil, False, False));
  Assert.AreEqual('test', TUnitSearch.KindOf(MakeUnit('Hilfe', 'a.pas', nil), nil, False, True), 'nur Testprojekte');
  Assert.AreEqual('form', TUnitSearch.KindOf(MakeUnit('A', 'a.pas', nil, 'TA', 'TUnbekannt'), nil, True, False),
    'mit .dfm ohne bekannte Kette');
  Assert.AreEqual('unit', TUnitSearch.KindOf(MakeUnit('A', 'a.pas', nil), nil, False, False));
end;

procedure TUnitSearchTests.HeaderCommentWithoutMarkers;
begin
  Assert.AreEqual('Kunden verwalten'#10'zweite Zeile', TUnitSearch.HeaderComment(
    '{$I Optionen.inc}'#13#10'// ----------'#13#10'// Kunden verwalten'#13#10'// zweite Zeile'#13#10#13#10 +
    'unit Kunden;'#13#10'// nicht mehr'));
  Assert.AreEqual('Block'#10'Mitte'#10'Ende', TUnitSearch.HeaderComment('{ Block'#10'  Mitte'#10'  Ende }'#10'unit X;'));
  Assert.AreEqual('', TUnitSearch.HeaderComment('unit X;'#10'// später'));
end;

procedure TUnitSearchTests.CountsLines;
begin
  Assert.AreEqual(0, TUnitSearch.LineCount(''));
  Assert.AreEqual(2, TUnitSearch.LineCount('a'#13#10'b'));
  Assert.AreEqual(2, TUnitSearch.LineCount('a'#13#10'b'#13#10));
end;

procedure TUnitSearchTests.GitStates;
begin
  Assert.AreEqual('', TUnitSearch.GitState(nil, False));
  Assert.AreEqual('clean', TUnitSearch.GitState(nil, True));
  Assert.AreEqual('modified', TUnitSearch.GitState([' M Kunden.pas'], True));
  Assert.AreEqual('modified', TUnitSearch.GitState(['MM Kunden.pas'], True));
  Assert.AreEqual('added', TUnitSearch.GitState(['A  Kunden.pas'], True));
  Assert.AreEqual('untracked', TUnitSearch.GitState(['?? Kunden.pas'], True));
  Assert.AreEqual('conflict', TUnitSearch.GitState(['UU Kunden.pas'], True));
  Assert.AreEqual('renamed', TUnitSearch.GitState(['R  Alt.pas -> Kunden.pas'], True));
end;

procedure TUnitSearchTests.SketchHandlesAlignAndNesting;
var
  Sketch: TUnitSketch;
begin
  Sketch := TUnitSearch.Sketch(FormText);
  Assert.AreEqual('THaupt', Sketch.FormClass);
  Assert.AreEqual('Kunden', Sketch.Caption);
  Assert.AreEqual(400, Sketch.Width);
  Assert.AreEqual(300, Sketch.Height);
  // Panel oben, Label darin, Liste im Rest; der Timer ist unsichtbar.
  Assert.AreEqual(3, Integer(Length(Sketch.Items)));
  Assert.AreEqual('Kopf', Sketch.Items[0].Name);
  Assert.AreEqual(0, Sketch.Items[0].Top);
  Assert.AreEqual(400, Sketch.Items[0].Width);
  Assert.AreEqual(40, Sketch.Items[0].Height);
  Assert.AreEqual('Titel', Sketch.Items[1].Caption);
  Assert.AreEqual(8, Sketch.Items[1].Left);
  Assert.AreEqual(2, Sketch.Items[1].Depth);
  Assert.AreEqual('Liste', Sketch.Items[2].Name);
  Assert.AreEqual(40, Sketch.Items[2].Top);
  Assert.AreEqual(260, Sketch.Items[2].Height);
  Assert.AreEqual('', TUnitSearch.Sketch('').FormClass);
end;

procedure TUnitSearchTests.UsedByListsProjectUnits;
var
  Names: TArray<string>;
begin
  Names := TUnitSearch.UsedBy(Context.Units, 'Kunden');
  Assert.AreEqual(2, Integer(Length(Names)));
  Assert.AreEqual('Haupt', Names[0]);
  Assert.AreEqual('Kunden.Tests', Names[1]);
  // Bibliotheks-Units zählen nicht.
  Assert.AreEqual(0, Integer(Length(TUnitSearch.UsedBy(Context.Units, 'Hilfe'))));
end;

function Find(AUnits: TJSONArray; const AName: string): TJSONObject;
var
  Item: TJSONValue;
begin
  for Item in AUnits do
    if TJSONObject(Item).GetValue<string>('name') = AName then
      Exit(TJSONObject(Item));
  Result := nil;
end;

procedure TUnitSearchTests.UnitsCarryOriginKindAndProjects;
var
  Answer: TJSONObject;
  Units: TJSONArray;
  Item: TJSONObject;
begin
  Answer := TUnitSearch.UnitsJson(Context);
  try
    Units := Answer.GetValue<TJSONArray>('units');
    Assert.AreEqual(7, Integer(Units.Count), Answer.ToJSON);
    Item := Find(Units, 'Kunden');
    Assert.AreEqual('project', Item.GetValue<string>('origin'));
    Assert.AreEqual('unit', Item.GetValue<string>('kind'), 'auch im Testprojekt, aber nicht nur dort');
    Assert.AreEqual(2, Integer(Item.GetValue<TJSONArray>('projects').Count));
    Assert.IsTrue(TDocumentUris.SameFile(TDocumentUris.FromPath('C:\P\Kunden.pas'), Item.GetValue<string>('uri')));
    Assert.AreEqual('form', Find(Units, 'Haupt').GetValue<string>('kind'));
    Item := Find(Units, 'Kunden.Tests');
    Assert.AreEqual('test', Item.GetValue<string>('kind'));
    Assert.AreEqual('Tests', Item.GetValue<TJSONArray>('projects').Items[0].Value);
    Assert.AreEqual('searchPath', Find(Units, 'Hilfe').GetValue<string>('origin'));
    Assert.AreEqual('library', Find(Units, 'System.SysUtils').GetValue<string>('origin'));
    Assert.AreEqual('inc', Find(Units, 'Optionen.inc').GetValue<string>('kind'));
    // Projektdatei ohne Indexeintrag, aber nicht die .dpr.
    Assert.AreEqual('project', Find(Units, 'Neu').GetValue<string>('origin'));
    Assert.IsNull(Find(Units, 'App'));
    Assert.AreEqual(2, Integer(Answer.GetValue<TJSONArray>('projects').Count));
    Assert.IsTrue(TJSONObject(Answer.GetValue<TJSONArray>('projects').Items[1]).GetValue<Boolean>('isTest'));
  finally
    Answer.Free;
  end;
end;

procedure TUnitSearchTests.PreviewWithoutOpening;
var
  Answer, Form: TJSONObject;
begin
  Answer := TUnitSearch.PreviewJson(Context, 'C:\P\Haupt.pas', True, True);
  try
    Assert.AreEqual('Hauptfenster'#10'der Anwendung', Answer.GetValue<string>('header'));
    Assert.AreEqual(5, Answer.GetValue<Integer>('lines'));
    Assert.AreEqual('modified', Answer.GetValue<string>('git'));
    Assert.IsTrue(Answer.GetValue<string>('modified').StartsWith('2026-10-15'));
    Assert.AreEqual('THaupt', TJSONObject(Answer.GetValue<TJSONArray>('types').Items[0]).GetValue<string>('name'));
    Assert.AreEqual(1, Answer.GetValue<Integer>('typeCount'));
    Assert.AreEqual(1, Integer(Answer.GetValue<TJSONArray>('uses').Count));
    Assert.AreEqual('Kunden', Answer.GetValue<TJSONArray>('uses').Items[0].Value);
    Assert.AreEqual(0, Answer.GetValue<Integer>('usedBy'));
    Form := Answer.GetValue<TJSONObject>('form');
    Assert.AreEqual(400, Form.GetValue<Integer>('width'));
    Assert.AreEqual(3, Integer(Form.GetValue<TJSONArray>('items').Count));
  finally
    Answer.Free;
  end;
  Answer := TUnitSearch.PreviewJson(Context, 'C:\P\Kunden.pas', False, True);
  try
    Assert.AreEqual(2, Answer.GetValue<Integer>('usedBy'));
    Assert.IsNull(Answer.GetValue('form'));
  finally
    Answer.Free;
  end;
  Answer := TUnitSearch.PreviewJson(Context, 'C:\P\Haupt.pas', False, False);
  try
    Assert.IsNull(Answer.GetValue('form'));
    Assert.IsNull(Answer.GetValue('usedBy'));
  finally
    Answer.Free;
  end;
end;

function DeclaringKunde(const AName: string): TArray<string>;
begin
  Result := nil;
  if SameText(AName, 'TKunde') then
    Result := ['Kunden'];
end;

procedure TUnitSearchTests.AddUsesBuildsWorkspaceEdit;
var
  Answer, Changes: TJSONObject;
  Edits: TJSONArray;
  UsesContext: TUsesContext;
begin
  UsesContext := Default(TUsesContext);
  UsesContext.Declaring := DeclaringKunde;
  Answer := TUnitSearch.AddUsesJson('file:///C:/P/Haupt.pas',
    'unit Haupt;'#13#10'interface'#13#10'uses'#13#10'  Basis;'#13#10'var K: TKunde;'#13#10 +
    'implementation'#13#10'end.', ['Kunden', 'Basis', 'Werkzeug'], UsesContext);
  try
    Assert.AreEqual('["Kunden","Werkzeug"]', Answer.GetValue<TJSONArray>('added').ToJSON);
    Changes := Answer.GetValue<TJSONObject>('edit.changes');
    Edits := Changes.Values['file:///C:/P/Haupt.pas'] as TJSONArray;
    Assert.AreEqual(2, Integer(Edits.Count));
    Assert.Contains(TJSONObject(Edits.Items[0]).GetValue<string>('newText') +
      TJSONObject(Edits.Items[1]).GetValue<string>('newText'), #13#10);
  finally
    Answer.Free;
  end;
  // Alles schon da: kein Edit.
  Answer := TUnitSearch.AddUsesJson('file:///C:/P/Haupt.pas', 'unit Haupt;'#10'interface'#10'uses Basis;'#10 +
    'implementation'#10'end.', ['Basis'], UsesContext);
  try
    Assert.IsTrue(Answer.GetValue('edit') is TJSONNull);
    Assert.AreEqual(0, Integer(Answer.GetValue<TJSONArray>('added').Count));
  finally
    Answer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TUnitSearchTests);

end.
