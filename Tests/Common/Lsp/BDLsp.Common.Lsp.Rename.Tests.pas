unit BDLsp.Common.Lsp.Rename.Tests;

// Tests für das Umbenennen im Projekt (#30).

interface

uses
  DUnitX.TestFramework,
  BDLsp.Common.Index.Contract,
  BDLsp.Common.Semantics.NameResolver,
  BDLsp.Common.Lsp.Rename;

type
  [TestFixture]
  TLspRenameTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function CheckAt(const AMarker: string; const AFiles: TArray<string>): TRenameCheck;
    function EditsAt(const AMarker, ANewName: string): TArray<TRenameEdit>;
    function FormEdits(const AMarker, ANewName: string; AHandlers: Boolean;
      AFmx: Boolean = False): TArray<TRenameEdit>;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ValidatesNewNames;
    [Test]
    procedure PrepareReturnsNameAndRange;
    [Test]
    procedure RejectsSymbolsOutsideProject;
    [Test]
    procedure RejectsUnitNames;
    [Test]
    procedure RenamesAcrossUnitsAndForm;
    [Test]
    procedure RejectsInvalidNewName;
    [Test]
    procedure RenamesComponentWithHandlers;
    [Test]
    procedure KeepsHandlersWhenDisabled;
    [Test]
    procedure RenamesHandlersInFmxViews;
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Pascal.SyntaxTree,
  BDLsp.Common.Pascal.Parser,
  BDLsp.Common.Index.SymbolIndex,
  BDLsp.Common.Index.Extractor;

const
  WerkzeugFile = 'C:\P\Werkzeug.pas';
  WerkzeugDfm = 'C:\P\Werkzeug.dfm';
  HauptFile = 'C:\P\Haupt.pas';

  UnitWerkzeug =
    'unit Werkzeug;'#10 +                            // 0
    'interface'#10 +                                 // 1
    'type'#10 +                                      // 2
    '  TRechner = class'#10 +                        // 3
    '    function Summe(A, B: Integer): Integer;'#10 + // 4
    '  end;'#10 +                                    // 5
    'implementation'#10 +                            // 6
    '{$R *.dfm}'#10 +                                // 7
    'function TRechner.Summe(A, B: Integer): Integer;'#10 + // 8
    'begin'#10 +                                     // 9
    '  Result := A + B;'#10 +                        // 10
    'end;'#10 +                                      // 11
    'end.';

  FormWerkzeug =
    'object Rechner: TRechner'#10 +
    '  OnSumme = Summe'#10 +
    '  object Summe: TButton'#10 +
    '    Caption = ''Summe'''#10 +
    '  end'#10 +
    'end';

  UnitHaupt =
    'unit Haupt;'#10 +                               // 0
    'interface'#10 +                                 // 1
    'uses Werkzeug;'#10 +                            // 2
    'implementation'#10 +                            // 3
    'procedure Lauf;'#10 +                           // 4
    'var'#10 +                                       // 5
    '  R: TRechner;'#10 +                            // 6
    'begin'#10 +                                     // 7
    '  R.Summe(1, 2);'#10 +                          // 8
    '  R.Summe(R.Summe(3, 4), 5);'#10 +              // 9
    'end;'#10 +                                      // 10
    'end.';

  MaskeFile = 'C:\P\Maske.pas';
  MaskeDfm = 'C:\P\Maske.dfm';
  MaskeFmx = 'C:\P\Maske.fmx';
  MaskeWindowsFmx = 'C:\P\Maske.Windows.fmx';

  UnitMaske =
    'unit Maske;'#10 +                               // 0
    'interface'#10 +                                 // 1
    'type'#10 +                                      // 2
    '  TMaske = class(TObject)'#10 +                 // 3
    '    Button1: TObject;'#10 +                     // 4
    '    procedure Button1Click(Sender: TObject);'#10 + // 5
    '    procedure Eigen(Sender: TObject);'#10 +     // 6
    '  end;'#10 +                                    // 7
    'implementation'#10 +                            // 8
    'procedure TMaske.Button1Click(Sender: TObject);'#10 + // 9
    'begin'#10 +                                     // 10
    '  Eigen(Button1);'#10 +                         // 11
    'end;'#10 +                                      // 12
    'procedure TMaske.Eigen(Sender: TObject);'#10 +  // 13
    'begin'#10 +                                     // 14
    'end;'#10 +                                      // 15
    'end.';

  FormMaske =
    'object Maske: TMaske'#10 +
    '  object Button1: TButton'#10 +
    '    OnClick = Button1Click'#10 +
    '    OnEnter = Eigen'#10 +
    '  end'#10 +
    'end';

function PositionOf(const AText, AMarker: string): TTextPosition;
var
  Index, Line, LineStart, I: Integer;
begin
  Index := Pos(AMarker, AText);
  if Index = 0 then
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
  Line := 0;
  LineStart := 1;
  for I := 1 to Index - 1 do
    if AText[I] = #10 then
    begin
      Inc(Line);
      LineStart := I + 1;
    end;
  Result := TTextPosition.Create(Line, Index - LineStart);
end;

{ TLspRenameTests }

procedure TLspRenameTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitWerkzeug, WerkzeugFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspRenameTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspRenameTests.CheckAt(const AMarker: string; const AFiles: TArray<string>): TRenameCheck;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    Result := TLspRename.Check(FResolver, FIndex, Tree, HauptFile, PositionOf(UnitHaupt, AMarker), AFiles);
  finally
    Tree.Free;
  end;
end;

function TLspRenameTests.EditsAt(const AMarker, ANewName: string): TArray<TRenameEdit>;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    Result := TLspRename.Edits(FResolver, FIndex, Tree, HauptFile, PositionOf(UnitHaupt, AMarker), ANewName,
      [WerkzeugFile, HauptFile],
      function(const AFileName: string; out AText: string): Boolean
      begin
        Result := True;
        if SameText(AFileName, WerkzeugFile) then
          AText := UnitWerkzeug
        else if SameText(AFileName, WerkzeugDfm) then
          AText := FormWerkzeug
        else
          Result := False;
      end);
  finally
    Tree.Free;
  end;
end;

function TLspRenameTests.FormEdits(const AMarker, ANewName: string; AHandlers: Boolean;
  AFmx: Boolean): TArray<TRenameEdit>;
var
  Index: ISymbolIndex;
  Resolver: TNameResolver;
  Tree: TSyntaxTree;
  UnitText: string;
begin
  // FMX (#87): Formular und Plattformansicht über die {$R}-Direktiven der Unit.
  UnitText := UnitMaske;
  if AFmx then
    UnitText := StringReplace(UnitText, 'implementation'#10,
      'implementation'#10'{$R *.fmx}'#10'{$R *.Windows.fmx MSWINDOWS}'#10, []);
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText(UnitText, MaskeFile, nil));
  Resolver := TNameResolver.Create(Index);
  Tree := TPascalParser.Parse(UnitText);
  try
    Result := TLspRename.Edits(Resolver, Index, Tree, MaskeFile, PositionOf(UnitText, AMarker), ANewName,
      [MaskeFile],
      function(const AFileName: string; out AText: string): Boolean
      begin
        Result := True;
        if SameText(AFileName, MaskeFile) then
          AText := UnitText
        else if not AFmx and SameText(AFileName, MaskeDfm) then
          AText := FormMaske
        else if AFmx and (SameText(AFileName, MaskeFmx) or SameText(AFileName, MaskeWindowsFmx)) then
          AText := FormMaske
        else
          Result := False;
      end, nil, AHandlers);
  finally
    Tree.Free;
    Resolver.Free;
  end;
end;

procedure TLspRenameTests.ValidatesNewNames;
begin
  Assert.IsTrue(TLspRename.IsValidName('Addiere'));
  Assert.IsTrue(TLspRename.IsValidName('_Wert2'));
  Assert.IsFalse(TLspRename.IsValidName(''));
  Assert.IsFalse(TLspRename.IsValidName('begin'));
  Assert.IsFalse(TLspRename.IsValidName('2Wert'));
  Assert.IsFalse(TLspRename.IsValidName('A B'));
  Assert.IsFalse(TLspRename.IsValidName('&Wert'));
end;

procedure TLspRenameTests.PrepareReturnsNameAndRange;
var
  Checked: TRenameCheck;
begin
  Checked := CheckAt('Summe(1', [WerkzeugFile]);
  Assert.AreEqual('', Checked.Error);
  Assert.AreEqual('Summe', Checked.Name);
  Assert.AreEqual(8, Checked.Range.StartPos.Line);
  Assert.AreEqual(4, Checked.Range.StartPos.Character);
  Assert.AreEqual(9, Checked.Range.EndPos.Character);
end;

procedure TLspRenameTests.RejectsSymbolsOutsideProject;
begin
  // Werkzeug.pas gehört hier nicht zum Projekt, wie eine Bibliotheks-Unit.
  Assert.IsTrue(Pos('außerhalb des Projekts', CheckAt('Summe(1', []).Error) > 0);
  Assert.AreNotEqual('', CheckAt('begin', [WerkzeugFile]).Error);
end;

procedure TLspRenameTests.RejectsUnitNames;
begin
  Assert.IsTrue(Pos('Dateinamen', CheckAt('Werkzeug;', [WerkzeugFile]).Error) > 0);
end;

procedure TLspRenameTests.RenamesAcrossUnitsAndForm;
var
  Found: TArray<TRenameEdit>;
  Edit: TRenameEdit;
  Haupt, Werkzeug, Form: Integer;
begin
  Found := EditsAt('Summe(1', 'Addiere');
  Haupt := 0;
  Werkzeug := 0;
  Form := 0;
  for Edit in Found do
    if SameText(Edit.FileName, HauptFile) then
      Inc(Haupt)
    else if SameText(Edit.FileName, WerkzeugFile) then
      Inc(Werkzeug)
    else if SameText(Edit.FileName, WerkzeugDfm) then
      Inc(Form);
  Assert.AreEqual(3, Haupt);
  Assert.AreEqual(2, Werkzeug);
  Assert.AreEqual(2, Form);
end;

procedure TLspRenameTests.RejectsInvalidNewName;
var
  Raised: Boolean;
begin
  Raised := False;
  try
    EditsAt('Summe(1', 'end');
  except
    on EJsonRpcError do
      Raised := True;
  end;
  Assert.IsTrue(Raised);
end;

procedure TLspRenameTests.RenamesComponentWithHandlers;
var
  Found: TArray<TRenameEdit>;
  Edit: TRenameEdit;
  Field, Handler, Other: Integer;
begin
  Found := FormEdits('Button1: TObject', 'btnSpeichern', True);
  Field := 0;
  Handler := 0;
  Other := 0;
  for Edit in Found do
    if Edit.NewText = 'btnSpeichern' then
      Inc(Field)
    else if Edit.NewText = 'btnSpeichernClick' then
      Inc(Handler)
    else
      Inc(Other);
  // Feld, Verwendung im Code und Objektname in der DFM.
  Assert.AreEqual(3, Field);
  // Deklaration, Implementierung und Zuordnung in der DFM; Eigen bleibt.
  Assert.AreEqual(3, Handler);
  Assert.AreEqual(0, Other);
end;

procedure TLspRenameTests.KeepsHandlersWhenDisabled;
var
  Edit: TRenameEdit;
begin
  for Edit in FormEdits('Button1: TObject', 'btnSpeichern', False) do
    Assert.AreEqual('btnSpeichern', Edit.NewText);
end;

procedure TLspRenameTests.RenamesHandlersInFmxViews;
var
  Edit: TRenameEdit;
  Fmx, Windows: Integer;
begin
  Fmx := 0;
  Windows := 0;
  for Edit in FormEdits('Button1: TObject', 'btnSpeichern', True, True) do
    if SameText(Edit.FileName, MaskeFmx) then
      Inc(Fmx)
    else if SameText(Edit.FileName, MaskeWindowsFmx) then
      Inc(Windows);
  // Objektname und Zuordnung OnClick in beiden Formularen.
  Assert.AreEqual(2, Fmx);
  Assert.AreEqual(2, Windows);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspRenameTests);

end.
