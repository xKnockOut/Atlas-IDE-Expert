unit Atlas.Common.Lsp.UnitSearch.Tests;

// Tests für die Daten des Fensters „Units suchen“ (#777): Art der Unit,
// Herkunft, Kopfkommentar, Git-Zustand, Formularskizze und „Verwendet von“;
// „In uses aufnehmen“ auch mit festem Abschnitt (#786).

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
    /// <summary>#1310: Caption des Wurzelobjekts, entschlüsselt und fortgesetzt, nie die eines Kindes.</summary>
    [Test]
    procedure FormCaptionReadsRootOnly;
    /// <summary>#1310: atlas.server.units liefert Captions nur auf Wunsch und nur für Formulare.</summary>
    [Test]
    procedure UnitsCarryFormCaptionsOnRequest;
    [Test]
    procedure PreviewWithoutOpening;
    [Test]
    procedure AddUsesBuildsWorkspaceEdit;
    [Test]
    procedure AddUsesTakesSection;
  end;

implementation

uses
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Editing.Contract;

function MakeUnit(const AName, AFile: string; const AUses: TArray<string>; const AClass: string;
  const AAncestor: string): TUnitIndex; overload;
var
  mSymbol: TIndexSymbol;
begin
  Result := Default(TUnitIndex);
  Result.UnitName := AName;
  Result.FileName := AFile;
  Result.InterfaceUses := AUses;
  if AClass <> '' then
  begin
    mSymbol := Default(TIndexSymbol);
    mSymbol.Name := AClass;
    mSymbol.Kind := TIndexSymbolKind.ClassType;
    mSymbol.InInterface := True;
    mSymbol.Ancestors := [AAncestor];
    Result.Symbols := [mSymbol];
  end;
end;

function MakeUnit(const AName, AFile: string; const AUses: TArray<string>): TUnitIndex; overload;
begin
  Result := MakeUnit(AName, AFile, AUses, '', '');
end;

function MakeUnit(const AName, AFile: string; const AUses: TArray<string>; const AClass: string): TUnitIndex; overload;
begin
  Result := MakeUnit(AName, AFile, AUses, AClass, '');
end;

function Chain(const AType: string): TArray<string>;
begin
  Result := nil;
  if SameText(AType, 'TBasisForm') then
  begin
    Result := ['Vcl.Forms.TForm'];
  end
  else if SameText(AType, 'TKreis') then
  begin
    Result := ['TKreis'];
  end;
end;

const
  cFormText =
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

/// <summary>Projekte App und Tests; Kunden.pas steht in beiden.</summary>
function UnitSearchProjects: TArray<TUnitSearchProject>;
var
  mMain, mTests: TUnitSearchProject;
begin
  mMain := Default(TUnitSearchProject);
  mMain.Name := 'App';
  mMain.FileName := 'C:\P\App.dproj';
  mMain.Files := ['C:\P\App.dpr', 'C:\P\Kunden.pas', 'C:\P\Haupt.pas', 'C:\P\Neu.pas'];
  mTests := Default(TUnitSearchProject);
  mTests.Name := 'Tests';
  mTests.FileName := 'C:\P\Tests\Tests.dproj';
  mTests.IsTest := True;
  mTests.Files := ['C:\P\Tests\Tests.dpr', 'C:\P\Tests\Kunden.Tests.pas', 'C:\P\Kunden.pas'];
  Result := [mMain, mTests];
end;

function TUnitSearchTests.Context: TUnitSearchContext;
var
  mKunden, mHaupt, mKundenTests, mHilfe, mSys: TUnitIndex;
begin
  mKunden := MakeUnit('Kunden', 'C:\P\Kunden.pas', ['System.SysUtils']);
  mKunden.Includes := ['C:\P\Optionen.inc'];
  mHaupt := MakeUnit('Haupt', 'C:\P\Haupt.pas', ['Kunden'], 'THaupt', 'TBasisForm');
  mKundenTests := MakeUnit('Kunden.Tests', 'C:\P\Tests\Kunden.Tests.pas', ['DUnitX.TestFramework', 'Kunden']);
  mHilfe := MakeUnit('Hilfe', 'C:\Lib\Hilfe.pas', nil);
  mSys := MakeUnit('System.SysUtils', 'C:\BDS\SysUtils.pas', nil);
  mSys.Library_ := True;
  Result := Default(TUnitSearchContext);
  Result.Units := [mKunden, mHaupt, mKundenTests, mHilfe, mSys];
  Result.Projects := UnitSearchProjects;
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
      begin
        Result := cFormText;
      end
      else if SameText(AFile, 'C:\P\Haupt.pas') then
      begin
        Result := '// Hauptfenster'#13#10'// der Anwendung'#13#10'unit Haupt;'#13#10'interface'#13#10'end.';
      end
      else
      begin
        Result := '';
      end;
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
  mAncestors: TFunc<string, TArray<string>>;
begin
  mAncestors :=
    function(AType: string): TArray<string>
    begin
      Result := Chain(AType);
    end;
  Assert.AreEqual('form', TUnitSearch.KindOf(MakeUnit('A', 'a.pas', nil, 'TA', 'TBasisForm'), mAncestors, False, False));
  Assert.AreEqual('frame', TUnitSearch.KindOf(MakeUnit('A', 'a.pas', nil, 'TA', 'TFrame'), mAncestors, True, False));
  Assert.AreEqual('dm', TUnitSearch.KindOf(MakeUnit('A', 'a.pas', nil, 'TA', 'TDataModule'), mAncestors, True, False));
  // Zyklus in der Kette bricht ab.
  Assert.AreEqual('unit', TUnitSearch.KindOf(MakeUnit('A', 'a.pas', nil, 'TA', 'TKreis'), mAncestors, False, False));
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
  mSketch: TUnitSketch;
begin
  mSketch := TUnitSearch.Sketch(cFormText);
  Assert.AreEqual('THaupt', mSketch.FormClass);
  Assert.AreEqual('Kunden', mSketch.Caption);
  Assert.AreEqual(400, mSketch.Width);
  Assert.AreEqual(300, mSketch.Height);
  // Panel oben, Label darin, Liste im Rest; der Timer ist unsichtbar.
  Assert.AreEqual(3, Integer(Length(mSketch.Items)));
  Assert.AreEqual('Kopf', mSketch.Items[0].Name);
  Assert.AreEqual(0, mSketch.Items[0].Top);
  Assert.AreEqual(400, mSketch.Items[0].Width);
  Assert.AreEqual(40, mSketch.Items[0].Height);
  Assert.AreEqual('Titel', mSketch.Items[1].Caption);
  Assert.AreEqual(8, mSketch.Items[1].Left);
  Assert.AreEqual(2, mSketch.Items[1].Depth);
  Assert.AreEqual('Liste', mSketch.Items[2].Name);
  Assert.AreEqual(40, mSketch.Items[2].Top);
  Assert.AreEqual(260, mSketch.Items[2].Height);
  Assert.AreEqual('', TUnitSearch.Sketch('').FormClass);
end;

procedure TUnitSearchTests.UsedByListsProjectUnits;
var
  mNames: TArray<string>;
begin
  mNames := TUnitSearch.UsedBy(Context.Units, 'Kunden');
  Assert.AreEqual(2, Integer(Length(mNames)));
  Assert.AreEqual('Haupt', mNames[0]);
  Assert.AreEqual('Kunden.Tests', mNames[1]);
  // Bibliotheks-Units zählen nicht.
  Assert.AreEqual(0, Integer(Length(TUnitSearch.UsedBy(Context.Units, 'Hilfe'))));
end;

function Find(AUnits: TJSONArray; const AName: string): TJSONObject;
var
  mItem: TJSONValue;
begin
  for mItem in AUnits do
  begin
    if TJSONObject(mItem).GetValue<string>('name') = AName then
    begin
      Exit(TJSONObject(mItem));
    end;
  end;
  Result := nil;
end;

procedure TUnitSearchTests.UnitsCarryOriginKindAndProjects;
var
  mAnswer: TJSONObject;
  mUnits: TJSONArray;
  mItem: TJSONObject;
begin
  mAnswer := TUnitSearch.UnitsJson(Context);
  try
    mUnits := mAnswer.GetValue<TJSONArray>('units');
    Assert.AreEqual(7, Integer(mUnits.Count), mAnswer.ToJSON);
    mItem := Find(mUnits, 'Kunden');
    Assert.AreEqual('project', mItem.GetValue<string>('origin'));
    Assert.AreEqual('unit', mItem.GetValue<string>('kind'), 'auch im Testprojekt, aber nicht nur dort');
    Assert.AreEqual(2, Integer(mItem.GetValue<TJSONArray>('projects').Count));
    Assert.IsTrue(TDocumentUris.SameFile(TDocumentUris.FromPath('C:\P\Kunden.pas'), mItem.GetValue<string>('uri')));
    Assert.AreEqual('form', Find(mUnits, 'Haupt').GetValue<string>('kind'));
    mItem := Find(mUnits, 'Kunden.Tests');
    Assert.AreEqual('test', mItem.GetValue<string>('kind'));
    Assert.AreEqual('Tests', mItem.GetValue<TJSONArray>('projects').Items[0].Value);
    Assert.AreEqual('searchPath', Find(mUnits, 'Hilfe').GetValue<string>('origin'));
    Assert.AreEqual('library', Find(mUnits, 'System.SysUtils').GetValue<string>('origin'));
    Assert.AreEqual('inc', Find(mUnits, 'Optionen.inc').GetValue<string>('kind'));
    // Projektdatei ohne Indexeintrag, aber nicht die .dpr.
    Assert.AreEqual('project', Find(mUnits, 'Neu').GetValue<string>('origin'));
    Assert.IsNull(Find(mUnits, 'App'));
    Assert.AreEqual(2, Integer(mAnswer.GetValue<TJSONArray>('projects').Count));
    Assert.IsTrue(TJSONObject(mAnswer.GetValue<TJSONArray>('projects').Items[1]).GetValue<Boolean>('isTest'));
  finally
    mAnswer.Free;
  end;
end;

procedure TUnitSearchTests.FormCaptionReadsRootOnly;
begin
  Assert.AreEqual('Kunden', TUnitSearch.FormCaption(cFormText));
  Assert.AreEqual('Kunden'#$E4'nderung', TUnitSearch.FormCaption(
    'inherited Pflege: TPflege'#13#10'  Caption = ''Kunden''#228''nderung'''#13#10'end'));
  // Lange Werte in Folgezeilen.
  Assert.AreEqual('Stammdaten der Kunden', TUnitSearch.FormCaption(
    'object F: TF'#13#10'  Caption ='#13#10'    ''Stammdaten '' +'#13#10'    ''der Kunden'''#13#10 +
    '  Width = 10'#13#10'end'));
  // Nur das Wurzelobjekt: Captions von Kindern und Collection-Einträgen zählen nicht.
  Assert.AreEqual('', TUnitSearch.FormCaption(
    'object F: TF'#13#10'  Columns = <'#13#10'    item'#13#10'      Caption = ''Spalte'''#13#10'    end>'#13#10 +
    '  object B: TButton'#13#10'    Caption = ''OK'''#13#10'  end'#13#10'end'));
  Assert.AreEqual('', TUnitSearch.FormCaption('object F: TF'#13#10'  CaptionX = ''Nein'''#13#10'end'));
  Assert.AreEqual('', TUnitSearch.FormCaption('TPF0'#0#1'F'));
  Assert.AreEqual('', TUnitSearch.FormCaption(''));
end;

procedure TUnitSearchTests.UnitsCarryFormCaptionsOnRequest;
var
  mSearch: TUnitSearch;
  mShared: TUnitSearchContext;
  mArguments: TJSONArray;
  mAnswer: TJSONValue;
  mUnits: TJSONArray;
  mPass: Integer;
begin
  mShared := Context;
  mSearch := TUnitSearch.Create(
    function(out AContext: TUnitSearchContext): Boolean
    begin
      AContext := mShared;
      Result := True;
    end);
  mArguments := TJSONArray.Create;
  try
    mAnswer := mSearch.ExecuteUnits(nil);
    try
      mUnits := TJSONObject(mAnswer).GetValue<TJSONArray>('units');
      Assert.IsNull(Find(mUnits, 'Haupt').GetValue('caption'), 'ohne Wunsch keine Caption');
    finally
      mAnswer.Free;
    end;
    mArguments.Add(TJSONObject.Create(TJSONPair.Create('captions', TJSONBool.Create(True))));
    // Zweiter Lauf aus dem Zwischenspeicher.
    for mPass := 1 to 2 do
    begin
      mAnswer := mSearch.ExecuteUnits(mArguments);
      try
        mUnits := TJSONObject(mAnswer).GetValue<TJSONArray>('units');
        Assert.AreEqual('Kunden', Find(mUnits, 'Haupt').GetValue<string>('caption'));
        Assert.IsNull(Find(mUnits, 'Kunden').GetValue('caption'), 'keine Formular-Unit');
      finally
        mAnswer.Free;
      end;
    end;
  finally
    mArguments.Free;
    mSearch.Free;
  end;
end;

procedure TUnitSearchTests.PreviewWithoutOpening;
var
  mAnswer, mForm: TJSONObject;
begin
  mAnswer := TUnitSearch.PreviewJson(Context, 'C:\P\Haupt.pas', True, True);
  try
    Assert.AreEqual('Hauptfenster'#10'der Anwendung', mAnswer.GetValue<string>('header'));
    Assert.AreEqual(5, mAnswer.GetValue<Integer>('lines'));
    Assert.AreEqual('modified', mAnswer.GetValue<string>('git'));
    Assert.IsTrue(mAnswer.GetValue<string>('modified').StartsWith('2026-10-15'));
    Assert.AreEqual('THaupt', TJSONObject(mAnswer.GetValue<TJSONArray>('types').Items[0]).GetValue<string>('name'));
    Assert.AreEqual(1, mAnswer.GetValue<Integer>('typeCount'));
    Assert.AreEqual(1, Integer(mAnswer.GetValue<TJSONArray>('uses').Count));
    Assert.AreEqual('Kunden', mAnswer.GetValue<TJSONArray>('uses').Items[0].Value);
    Assert.AreEqual(0, mAnswer.GetValue<Integer>('usedBy'));
    mForm := mAnswer.GetValue<TJSONObject>('form');
    Assert.AreEqual(400, mForm.GetValue<Integer>('width'));
    Assert.AreEqual(3, Integer(mForm.GetValue<TJSONArray>('items').Count));
  finally
    mAnswer.Free;
  end;
  mAnswer := TUnitSearch.PreviewJson(Context, 'C:\P\Kunden.pas', False, True);
  try
    Assert.AreEqual(2, mAnswer.GetValue<Integer>('usedBy'));
    Assert.IsNull(mAnswer.GetValue('form'));
  finally
    mAnswer.Free;
  end;
  mAnswer := TUnitSearch.PreviewJson(Context, 'C:\P\Haupt.pas', False, False);
  try
    Assert.IsNull(mAnswer.GetValue('form'));
    Assert.IsNull(mAnswer.GetValue('usedBy'));
  finally
    mAnswer.Free;
  end;
end;

function DeclaringKunde(const AName: string): TArray<string>;
begin
  Result := nil;
  if SameText(AName, 'TKunde') then
  begin
    Result := ['Kunden'];
  end;
end;

procedure TUnitSearchTests.AddUsesBuildsWorkspaceEdit;
var
  mAnswer, mChanges: TJSONObject;
  mEdits: TJSONArray;
  mUsesContext: TUsesContext;
begin
  mUsesContext := Default(TUsesContext);
  mUsesContext.Declaring := DeclaringKunde;
  mAnswer := TUnitSearch.AddUsesJson('file:///C:/P/Haupt.pas',
    'unit Haupt;'#13#10'interface'#13#10'uses'#13#10'  Basis;'#13#10'var K: TKunde;'#13#10 +
    'implementation'#13#10'end.', ['Kunden', 'Basis', 'Werkzeug'], mUsesContext);
  try
    Assert.AreEqual('["Kunden","Werkzeug"]', mAnswer.GetValue<TJSONArray>('added').ToJSON);
    mChanges := mAnswer.GetValue<TJSONObject>('edit.changes');
    mEdits := mChanges.Values['file:///C:/P/Haupt.pas'] as TJSONArray;
    Assert.AreEqual(2, Integer(mEdits.Count));
    Assert.Contains(TJSONObject(mEdits.Items[0]).GetValue<string>('newText') +
      TJSONObject(mEdits.Items[1]).GetValue<string>('newText'), #13#10);
  finally
    mAnswer.Free;
  end;
  // Alles schon da: kein Edit.
  mAnswer := TUnitSearch.AddUsesJson('file:///C:/P/Haupt.pas', 'unit Haupt;'#10'interface'#10'uses Basis;'#10 +
    'implementation'#10'end.', ['Basis'], mUsesContext);
  try
    Assert.IsTrue(mAnswer.GetValue('edit') is TJSONNull);
    Assert.AreEqual(0, Integer(mAnswer.GetValue<TJSONArray>('added').Count));
  finally
    mAnswer.Free;
  end;
end;

function NewText(const AEdits: TJSONArray): string;
var
  mItem: TJSONValue;
begin
  Result := '';
  for mItem in AEdits do
  begin
    Result := Result + (mItem as TJSONObject).GetValue<string>('newText');
  end;
end;

procedure TUnitSearchTests.AddUsesTakesSection;
var
  mSearch: TUnitSearch;
  mArgs, mNames: TJSONArray;
  mSection: TJSONObject;
  mAnswer: TJSONValue;
  mEdits: TJSONArray;
begin
  mSearch := TUnitSearch.Create(
    function(out AContext: TUnitSearchContext): Boolean
    begin
      AContext := Default(TUnitSearchContext);
      AContext.ReadText :=
        function(AFile: string): string
        begin
          Result := 'unit Haupt;'#10'interface'#10'uses'#10'  Basis;'#10'implementation'#10'end.';
        end;
      Result := True;
    end);
  try
    // Ohne Abschnitt käme Werkzeug ins implementation-uses (der interface-Teil nennt nichts daraus).
    mArgs := TJSONArray.Create;
    try
      mArgs.Add('file:///C:/P/Haupt.pas');
      mNames := TJSONArray.Create;
      mNames.Add('Werkzeug');
      mArgs.AddElement(mNames);
      mSection := TJSONObject.Create;
      mSection.AddPair('section', 'interface');
      mArgs.AddElement(mSection);
      mAnswer := mSearch.ExecuteAddUses(mArgs);
      try
        mEdits := (mAnswer as TJSONObject).GetValue<TJSONObject>('edit.changes').Pairs[0].JsonValue as TJSONArray;
        Assert.AreEqual(1, Integer(mEdits.Count));
        // Angehängt an die interface-Liste: Komma hinter Basis, kein neues uses.
        Assert.IsFalse(NewText(mEdits).Contains('uses'), NewText(mEdits));
        Assert.AreEqual('["Werkzeug"]', (mAnswer as TJSONObject).GetValue<TJSONArray>('added').ToJSON);
      finally
        mAnswer.Free;
      end;
      mArgs.Remove(2).Free;
      mSection := TJSONObject.Create;
      mSection.AddPair('section', 'implementation');
      mArgs.AddElement(mSection);
      mAnswer := mSearch.ExecuteAddUses(mArgs);
      try
        mEdits := (mAnswer as TJSONObject).GetValue<TJSONObject>('edit.changes').Pairs[0].JsonValue as TJSONArray;
        Assert.IsTrue(NewText(mEdits).Contains('uses'), 'neues implementation-uses');
      finally
        mAnswer.Free;
      end;
    finally
      mArgs.Free;
    end;
  finally
    mSearch.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TUnitSearchTests);

end.
