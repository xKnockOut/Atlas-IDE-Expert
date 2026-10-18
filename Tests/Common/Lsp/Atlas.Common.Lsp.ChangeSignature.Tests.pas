unit Atlas.Common.Lsp.ChangeSignature.Tests;

// Tests für „Signatur ändern“ im Projekt (#100): Überschreibungen, Interfaces,
// Aufrufer in anderen Units, gebundene Handler, Abbruch- und Warnfälle.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Lsp.ChangeSignature;

type
  [TestFixture]
  TLspChangeSignatureTests = class
  private
    FIndex: ISymbolIndex;
    FTexts: TArray<string>;
    FFiles: TArray<string>;
    FReadOnly: string;
    procedure AddFile(const AFileName, AText: string);
    function TextOf(const AFileName: string): string;
    function Info(const AFileName, AMarker: string): TChangeSignatureInfo;
    function Run(const AFileName, AMarker: string; const AChanges: TArray<TParameterChange>;
      AMode: TNewParameterMode): TChangeSignatureOutcome; overload;
    function Run(const AFileName, AMarker: string; const AChanges: TArray<TParameterChange>;
      AMode: TNewParameterMode; AVirtual: Boolean): TChangeSignatureOutcome; overload;
    function Error(const AFileName, AMarker: string; const AChanges: TArray<TParameterChange>): string;
    function Applied(const AOutcome: TChangeSignatureOutcome; const AFileName: string): string;
    procedure AssertParses(const AOutcome: TChangeSignatureOutcome);
    procedure LoadProject;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure PrepareListsParametersAndMembers;
    [Test]
    procedure OverloadKeepsOldSignature;
    [Test]
    procedure VirtualOverloadOnRequest;
    [Test]
    procedure UpdateCallersPassesValue;
    [Test]
    procedure ReorderChangesCallersInAllUnits;
    [Test]
    procedure RemovesUnusedParameter;
    [Test]
    procedure RejectsRemovingUsedParameter;
    [Test]
    procedure RenamesParameterEverywhere;
    [Test]
    procedure InterfaceForcesUpdateCallers;
    [Test]
    procedure StartsFromOverrideOrCall;
    [Test]
    procedure RejectsLibraryEventHandler;
    [Test]
    procedure ChangesProjectEventType;
    [Test]
    procedure RejectsCollidingOverload;
    [Test]
    procedure WarnsAboutPointersAndReadOnlyCallers;
    [Test]
    procedure RoutineWithoutDeclaration;
    [Test]
    procedure OffersActionOnlyWhenEnabled;
    [Test]
    procedure ReadsRequestJson;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Rename;

const
  BasisFile = 'C:\P\Basis.pas';
  HauptFile = 'C:\P\Haupt.pas';
  MaskeFile = 'C:\P\Maske.pas';
  MaskeDfm = 'C:\P\Maske.dfm';
  KlassenFile = 'C:\Lib\Klassen.pas';

  UnitBasis =
    'unit Basis;'#10 +
    'interface'#10 +
    'type'#10 +
    '  IRechner = interface'#10 +
    '    function Summe(A, B: Integer): Integer;'#10 +
    '  end;'#10 +
    '  TBasis = class'#10 +
    '    /// <param name="Anzahl">Wie oft</param>'#10 +
    '    procedure Zeige(const Text: string; Anzahl: Integer); virtual;'#10 +
    '    function Teile(A, B: Integer): Integer;'#10 +
    '    procedure Leer(A: Integer; B: Integer);'#10 +
    '  end;'#10 +
    '  TKind = class(TBasis)'#10 +
    '    procedure Zeige(const Text: string; Anzahl: Integer); override;'#10 +
    '  end;'#10 +
    '  TRechner = class(TInterfacedObject, IRechner)'#10 +
    '    function Summe(A, B: Integer): Integer;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TBasis.Zeige(const Text: string; Anzahl: Integer);'#10 +
    'begin'#10 +
    '  Writeln(Text, Anzahl);'#10 +
    'end;'#10 +
    'function TBasis.Teile(A, B: Integer): Integer;'#10 +
    'begin'#10 +
    '  Result := A div B;'#10 +
    'end;'#10 +
    'procedure TBasis.Leer(A: Integer; B: Integer);'#10 +
    'begin'#10 +
    '  Writeln(B);'#10 +
    'end;'#10 +
    'procedure TKind.Zeige(const Text: string; Anzahl: Integer);'#10 +
    'begin'#10 +
    '  inherited Zeige(Text, Anzahl);'#10 +
    'end;'#10 +
    'function TRechner.Summe(A, B: Integer): Integer;'#10 +
    'begin'#10 +
    '  Result := A + B;'#10 +
    'end;'#10 +
    'end.';

  UnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Basis;'#10 +
    'implementation'#10 +
    'procedure Lauf;'#10 +
    'var'#10 +
    '  B: TBasis;'#10 +
    '  K: TKind;'#10 +
    '  R: IRechner;'#10 +
    'begin'#10 +
    '  B.Zeige(''x'', 1);'#10 +
    '  K.Zeige(''y'', 2);'#10 +
    '  B.Teile(6, 2);'#10 +
    '  B.Teile(B.Teile(8, 4), 2);'#10 +
    '  B.Leer(1, 2);'#10 +
    '  R.Summe(1, 2);'#10 +
    'end;'#10 +
    'end.';

  UnitKlassen =
    'unit Klassen;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TNotifyEvent = procedure(Sender: TObject) of object;'#10 +
    '  TControl = class'#10 +
    '  published'#10 +
    '    property OnClick: TNotifyEvent read FOnClick write FOnClick;'#10 +
    '  end;'#10 +
    '  TButton = class(TControl)'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

  UnitMaske =
    'unit Maske;'#10 +
    'interface'#10 +
    'uses Klassen;'#10 +
    'type'#10 +
    '  TWertEvent = procedure(Sender: TObject; Wert: Integer) of object;'#10 +
    '  TWertBox = class(TControl)'#10 +
    '  published'#10 +
    '    property OnWert: TWertEvent read FOnWert write FOnWert;'#10 +
    '  end;'#10 +
    '  TMaske = class(TObject)'#10 +
    '    Button1: TButton;'#10 +
    '    Box1: TWertBox;'#10 +
    '    procedure Button1Click(Sender: TObject);'#10 +
    '    procedure BoxWert(Sender: TObject; Wert: Integer);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    '{$R *.dfm}'#10 +
    'procedure TMaske.Button1Click(Sender: TObject);'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TMaske.BoxWert(Sender: TObject; Wert: Integer);'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  FormMaske =
    'object Maske: TMaske'#10 +
    '  object Button1: TButton'#10 +
    '    OnClick = Button1Click'#10 +
    '  end'#10 +
    '  object Box1: TWertBox'#10 +
    '    OnWert = BoxWert'#10 +
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

function Count(const AText, APart: string): Integer;
var
  Offset: Integer;
begin
  Result := 0;
  Offset := PosEx(APart, AText, 1);
  while Offset > 0 do
  begin
    Inc(Result);
    Offset := PosEx(APart, AText, Offset + 1);
  end;
end;

{ TLspChangeSignatureTests }

procedure TLspChangeSignatureTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FTexts := nil;
  FFiles := nil;
  FReadOnly := '';
end;

procedure TLspChangeSignatureTests.TearDown;
begin
  FIndex := nil;
  FTexts := nil;
  FFiles := nil;
  FReadOnly := '';
end;

procedure TLspChangeSignatureTests.AddFile(const AFileName, AText: string);
begin
  FFiles := FFiles + [AFileName];
  FTexts := FTexts + [AText];
  if SameText(ExtractFileExt(AFileName), '.pas') then
    FIndex.AddUnit(TIndexExtractor.ExtractText(AText, AFileName, nil));
end;

function TLspChangeSignatureTests.TextOf(const AFileName: string): string;
var
  Index: Integer;
begin
  for Index := 0 to High(FFiles) do
    if SameText(FFiles[Index], AFileName) then
      Exit(FTexts[Index]);
  Result := '';
end;

procedure TLspChangeSignatureTests.LoadProject;
begin
  AddFile(BasisFile, UnitBasis);
  AddFile(HauptFile, UnitHaupt);
end;

function TLspChangeSignatureTests.Info(const AFileName, AMarker: string): TChangeSignatureInfo;
var
  Resolver: TNameResolver;
  Tree: TSyntaxTree;
  Text: string;
begin
  Text := TextOf(AFileName);
  Resolver := TNameResolver.Create(FIndex);
  Tree := TPascalParser.Parse(Text);
  try
    Result := TLspChangeSignature.Prepare(Resolver, FIndex, Tree, AFileName, PositionOf(Text, AMarker),
      [BasisFile, HauptFile, MaskeFile, MaskeDfm],
      function(const AName: string; out AText: string): Boolean
      begin
        AText := TextOf(AName);
        Result := AText <> '';
      end, nil);
  finally
    Tree.Free;
    Resolver.Free;
  end;
end;

function TLspChangeSignatureTests.Run(const AFileName, AMarker: string; const AChanges: TArray<TParameterChange>;
  AMode: TNewParameterMode): TChangeSignatureOutcome;
begin
  Result := Run(AFileName, AMarker, AChanges, AMode, False);
end;

function TLspChangeSignatureTests.Run(const AFileName, AMarker: string; const AChanges: TArray<TParameterChange>;
  AMode: TNewParameterMode; AVirtual: Boolean): TChangeSignatureOutcome;
var
  Resolver: TNameResolver;
  Tree: TSyntaxTree;
  Text: string;
  Request: TChangeSignatureRequest;
begin
  Text := TextOf(AFileName);
  Request.Changes := AChanges;
  Request.Mode := AMode;
  Request.VirtualOverload := AVirtual;
  Resolver := TNameResolver.Create(FIndex);
  Tree := TPascalParser.Parse(Text);
  try
    Result := TLspChangeSignature.Execute(Resolver, FIndex, Tree, AFileName, PositionOf(Text, AMarker), Request,
      [BasisFile, HauptFile, MaskeFile, MaskeDfm],
      function(const AName: string; out AText: string): Boolean
      begin
        AText := TextOf(AName);
        Result := AText <> '';
      end,
      function(const AName: string): Boolean
      begin
        Result := SameText(AName, FReadOnly);
      end, nil);
  finally
    Tree.Free;
    Resolver.Free;
  end;
end;

function TLspChangeSignatureTests.Error(const AFileName, AMarker: string;
  const AChanges: TArray<TParameterChange>): string;
begin
  Result := '';
  try
    Run(AFileName, AMarker, AChanges, TNewParameterMode.UpdateCallers);
  except
    on E: EJsonRpcError do
      Result := E.Message;
  end;
end;

function TLspChangeSignatureTests.Applied(const AOutcome: TChangeSignatureOutcome; const AFileName: string): string;
var
  Edits: TArray<TTextEdit>;
  Edit: TRenameEdit;
begin
  Edits := nil;
  for Edit in AOutcome.Edits do
    if SameText(Edit.FileName, AFileName) then
      Edits := Edits + [TTextEdit.Create(Edit.Range, Edit.NewText)];
  Result := TChangeSignature.ApplyEdits(TextOf(AFileName), Edits);
end;

procedure TLspChangeSignatureTests.AssertParses(const AOutcome: TChangeSignatureOutcome);
var
  Tree: TSyntaxTree;
  FileName: string;
begin
  for FileName in [BasisFile, HauptFile, MaskeFile] do
  begin
    if TextOf(FileName) = '' then
      Continue;
    Tree := TPascalParser.Parse(Applied(AOutcome, FileName));
    try
      Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)), FileName);
    finally
      Tree.Free;
    end;
  end;
end;

procedure TLspChangeSignatureTests.PrepareListsParametersAndMembers;
var
  Found: TChangeSignatureInfo;
begin
  LoadProject;
  Found := Info(BasisFile, 'Zeige(const Text: string; Anzahl: Integer); override');
  Assert.AreEqual('Zeige', Found.Name);
  Assert.AreEqual('TBasis', Found.Container);
  Assert.AreEqual('procedure', Found.Keyword);
  Assert.AreEqual(2, Integer(Length(Found.Parameters)));
  Assert.AreEqual('const', Found.Parameters[0].Modifier);
  // Deklaration in TBasis und die Überschreibung in TKind.
  Assert.AreEqual(2, Found.Members);
  Assert.IsFalse(Found.InterfaceMethod);
end;

procedure TLspChangeSignatureTests.OverloadKeepsOldSignature;
var
  Outcome: TChangeSignatureOutcome;
  Basis: string;
begin
  LoadProject;
  Outcome := Run(BasisFile, 'Zeige(const Text: string; Anzahl: Integer); virtual', [TParameterChange.Kept(0, 'Text'),
    TParameterChange.Kept(1, 'Anzahl'), TParameterChange.Added('Farbe', 'Integer', '', 'clBlack')],
    TNewParameterMode.Overload);
  Assert.AreEqual(Ord(TNewParameterMode.Overload), Ord(Outcome.Mode));
  Basis := Applied(Outcome, BasisFile);
  Assert.Contains(Basis, '    procedure Zeige(const Text: string; Anzahl: Integer; Farbe: Integer); overload; virtual;'#10 +
    '    procedure Zeige(const Text: string; Anzahl: Integer); overload;'#10);
  Assert.Contains(Basis, 'procedure Zeige(const Text: string; Anzahl: Integer; Farbe: Integer); overload; override;');
  Assert.Contains(Basis, 'procedure TBasis.Zeige(const Text: string; Anzahl: Integer; Farbe: Integer);'#10'begin');
  Assert.Contains(Basis, 'procedure TBasis.Zeige(const Text: string; Anzahl: Integer);'#10'begin'#10 +
    '  Zeige(Text, Anzahl, clBlack);'#10'end;');
  // Die Überschreibung reicht den neuen Parameter weiter, statt sich über die alte Überladung selbst aufzurufen.
  Assert.Contains(Basis, '  inherited Zeige(Text, Anzahl, Farbe);');
  Assert.AreEqual(UnitHaupt, Applied(Outcome, HauptFile));
  Assert.AreEqual(0, Count(Basis, 'Farbe: Integer ='));
  AssertParses(Outcome);
end;

procedure TLspChangeSignatureTests.VirtualOverloadOnRequest;
var
  Outcome: TChangeSignatureOutcome;
begin
  LoadProject;
  Outcome := Run(BasisFile, 'Zeige(const Text: string; Anzahl: Integer); virtual', [TParameterChange.Kept(0, 'Text'),
    TParameterChange.Kept(1, 'Anzahl'), TParameterChange.Added('Farbe', 'Integer', '', '0')],
    TNewParameterMode.Overload, True);
  Assert.Contains(Applied(Outcome, BasisFile), 'procedure Zeige(const Text: string; Anzahl: Integer); overload; virtual;');
end;

procedure TLspChangeSignatureTests.UpdateCallersPassesValue;
var
  Outcome: TChangeSignatureOutcome;
  Basis, Haupt: string;
begin
  LoadProject;
  Outcome := Run(BasisFile, 'Zeige(const Text: string; Anzahl: Integer); virtual', [TParameterChange.Kept(0, 'Text'),
    TParameterChange.Kept(1, 'Anzahl'), TParameterChange.Added('Farbe', 'Integer', '', '0')],
    TNewParameterMode.UpdateCallers);
  Basis := Applied(Outcome, BasisFile);
  Haupt := Applied(Outcome, HauptFile);
  Assert.Contains(Haupt, 'B.Zeige(''x'', 1, 0);');
  Assert.Contains(Haupt, 'K.Zeige(''y'', 2, 0);');
  Assert.Contains(Basis, '  inherited Zeige(Text, Anzahl, Farbe);');
  Assert.AreEqual(0, Count(Basis, 'overload'));
  Assert.AreEqual(4, Count(Basis, 'Anzahl: Integer; Farbe: Integer)'));
  AssertParses(Outcome);
end;

procedure TLspChangeSignatureTests.ReorderChangesCallersInAllUnits;
var
  Outcome: TChangeSignatureOutcome;
  Haupt: string;
begin
  LoadProject;
  Outcome := Run(HauptFile, 'Teile(6', [TParameterChange.Kept(1, 'B'), TParameterChange.Kept(0, 'A')],
    TNewParameterMode.Overload);
  Haupt := Applied(Outcome, HauptFile);
  Assert.Contains(Haupt, 'B.Teile(2, 6);');
  Assert.Contains(Haupt, 'B.Teile(2, B.Teile(4, 8));');
  Assert.Contains(Applied(Outcome, BasisFile), 'function TBasis.Teile(B, A: Integer): Integer;');
  Assert.Contains(Applied(Outcome, BasisFile), '    function Teile(B, A: Integer): Integer;');
  AssertParses(Outcome);
end;

procedure TLspChangeSignatureTests.RemovesUnusedParameter;
var
  Outcome: TChangeSignatureOutcome;
begin
  LoadProject;
  Outcome := Run(BasisFile, 'Leer(A: Integer; B: Integer);'#10'  end', [TParameterChange.Kept(1, 'B')],
    TNewParameterMode.Overload);
  Assert.Contains(Applied(Outcome, HauptFile), 'B.Leer(2);');
  Assert.Contains(Applied(Outcome, BasisFile), 'procedure TBasis.Leer(B: Integer);');
  AssertParses(Outcome);
end;

procedure TLspChangeSignatureTests.RejectsRemovingUsedParameter;
begin
  LoadProject;
  Assert.Contains(Error(BasisFile, 'Teile(A, B: Integer): Integer;'#10'    procedure', [TParameterChange.Kept(0, 'A')]),
    'Zeile 26');
end;

procedure TLspChangeSignatureTests.RenamesParameterEverywhere;
var
  Outcome: TChangeSignatureOutcome;
  Basis: string;
begin
  LoadProject;
  Outcome := Run(BasisFile, 'Zeige(const Text: string; Anzahl: Integer); virtual', [TParameterChange.Kept(0, 'Text'),
    TParameterChange.Kept(1, 'Menge')], TNewParameterMode.Overload);
  Basis := Applied(Outcome, BasisFile);
  Assert.Contains(Basis, '/// <param name="Menge">Wie oft</param>');
  Assert.Contains(Basis, '  Writeln(Text, Menge);');
  Assert.Contains(Basis, '  inherited Zeige(Text, Menge);');
  Assert.AreEqual(0, Count(Basis, 'Anzahl'));
  Assert.AreEqual(UnitHaupt, Applied(Outcome, HauptFile));
  AssertParses(Outcome);
end;

procedure TLspChangeSignatureTests.InterfaceForcesUpdateCallers;
var
  Outcome: TChangeSignatureOutcome;
  Basis: string;
begin
  LoadProject;
  Assert.IsTrue(Info(BasisFile, 'Summe(A, B: Integer): Integer;'#10'  end;'#10'  TBasis').InterfaceMethod);
  Outcome := Run(BasisFile, 'Summe(A, B: Integer): Integer;'#10'  end;'#10'  TBasis', [TParameterChange.Kept(0, 'A'),
    TParameterChange.Kept(1, 'B'), TParameterChange.Added('C', 'Integer', '', '0')], TNewParameterMode.Overload);
  Assert.AreEqual(Ord(TNewParameterMode.UpdateCallers), Ord(Outcome.Mode));
  Basis := Applied(Outcome, BasisFile);
  Assert.AreEqual(3, Count(Basis, 'Summe(A, B: Integer; C: Integer): Integer;'));
  Assert.Contains(Applied(Outcome, HauptFile), 'R.Summe(1, 2, 0);');
  Assert.AreEqual(0, Count(Basis, 'overload'));
  AssertParses(Outcome);
end;

procedure TLspChangeSignatureTests.StartsFromOverrideOrCall;
begin
  LoadProject;
  // Von der Überschreibung, vom Rumpf und vom Aufruf aus dieselbe Kette.
  Assert.AreEqual('TBasis', Info(BasisFile, 'Zeige(const Text: string; Anzahl: Integer); override').Container);
  Assert.AreEqual('TBasis', Info(BasisFile, 'Zeige(Text, Anzahl);').Container);
  Assert.AreEqual(2, Info(HauptFile, 'Zeige(''y''').Members);
end;

procedure TLspChangeSignatureTests.RejectsLibraryEventHandler;
var
  Outcome: TChangeSignatureOutcome;
  Found: TChangeSignatureInfo;
begin
  AddFile(KlassenFile, UnitKlassen);
  AddFile(MaskeFile, UnitMaske);
  AddFile(MaskeDfm, FormMaske);
  Found := Info(MaskeFile, 'Button1Click(Sender: TObject);'#10'    procedure');
  Assert.AreEqual('TNotifyEvent', Found.BoundEvent);
  Assert.IsTrue(Found.EventFixed);
  Assert.Contains(Error(MaskeFile, 'Button1Click(Sender: TObject);'#10'    procedure',
    [TParameterChange.Kept(0, 'Sender'), TParameterChange.Added('X', 'Integer', '', '0')]), 'TNotifyEvent');
  // Umbenennen bleibt möglich.
  Outcome := Run(MaskeFile, 'Button1Click(Sender: TObject);'#10'    procedure', [TParameterChange.Kept(0, 'Quelle')],
    TNewParameterMode.Overload);
  Assert.Contains(Applied(Outcome, MaskeFile), 'procedure TMaske.Button1Click(Quelle: TObject);');
end;

procedure TLspChangeSignatureTests.ChangesProjectEventType;
var
  Outcome: TChangeSignatureOutcome;
  Maske: string;
begin
  AddFile(KlassenFile, UnitKlassen);
  AddFile(MaskeFile, UnitMaske);
  AddFile(MaskeDfm, FormMaske);
  Outcome := Run(MaskeFile, 'BoxWert(Sender: TObject; Wert: Integer);'#10'  end', [TParameterChange.Kept(0, 'Sender'),
    TParameterChange.Kept(1, 'Wert'), TParameterChange.Added('Alt', 'Integer', '', '0')], TNewParameterMode.Overload);
  // Gebundener Handler: keine Überladung, der Ereignistyp ändert sich mit.
  Assert.AreEqual(Ord(TNewParameterMode.UpdateCallers), Ord(Outcome.Mode));
  Maske := Applied(Outcome, MaskeFile);
  Assert.Contains(Maske, 'TWertEvent = procedure(Sender: TObject; Wert: Integer; Alt: Integer) of object;');
  Assert.Contains(Maske, 'procedure TMaske.BoxWert(Sender: TObject; Wert: Integer; Alt: Integer);');
  Assert.IsTrue(Length(Outcome.Warnings) > 0);
  AssertParses(Outcome);
end;

procedure TLspChangeSignatureTests.RejectsCollidingOverload;
var
  Text: string;
begin
  Text := StringReplace(UnitBasis, '    function Teile(A, B: Integer): Integer;'#10,
    '    function Teile(A, B: Integer): Integer; overload;'#10 +
    '    function Teile(A, B, C: Integer): Integer; overload;'#10, []);
  AddFile(BasisFile, Text);
  AddFile(HauptFile, UnitHaupt);
  Assert.Contains(Error(BasisFile, 'Teile(A, B: Integer): Integer; overload', [TParameterChange.Kept(0, 'A'),
    TParameterChange.Kept(1, 'B'), TParameterChange.Added('C', 'Integer', '', '0')]), 'kollidiert');
end;

procedure TLspChangeSignatureTests.WarnsAboutPointersAndReadOnlyCallers;
var
  Outcome: TChangeSignatureOutcome;
  Text: string;
begin
  Text := StringReplace(UnitHaupt, '  R.Summe(1, 2);'#10, '  R.Summe(1, 2);'#10'  P := @B.Teile;'#10, []);
  AddFile(BasisFile, UnitBasis);
  AddFile(HauptFile, Text);
  FReadOnly := HauptFile;
  Outcome := Run(BasisFile, 'Teile(A, B: Integer): Integer;'#10'    procedure', [TParameterChange.Kept(1, 'B'),
    TParameterChange.Kept(0, 'A')], TNewParameterMode.Overload);
  Assert.AreEqual(Text, Applied(Outcome, HauptFile));
  Assert.Contains(string.Join(#10, Outcome.Warnings), 'Methodenzeiger');
  Assert.Contains(string.Join(#10, Outcome.Warnings), 'Haupt.pas');
  // Die Deklaration selbst schreibgeschützt: Abbruch.
  FReadOnly := BasisFile;
  Assert.Contains(Error(BasisFile, 'Teile(A, B: Integer): Integer;'#10'    procedure', [TParameterChange.Kept(1, 'B'),
    TParameterChange.Kept(0, 'A')]), 'Basis.pas');
end;

procedure TLspChangeSignatureTests.RoutineWithoutDeclaration;
const
  UnitHilfe =
    'unit Hilfe;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'function Doppelt(A: Integer): Integer;'#10 +
    'begin'#10 +
    '  Result := A * 2;'#10 +
    'end;'#10 +
    'procedure Lauf;'#10 +
    'begin'#10 +
    '  Doppelt(3);'#10 +
    'end;'#10 +
    'end.';
var
  Outcome: TChangeSignatureOutcome;
  Hilfe: string;
begin
  AddFile(BasisFile, UnitHilfe);
  Outcome := Run(BasisFile, 'Doppelt(A: Integer)', [TParameterChange.Kept(0, 'A'),
    TParameterChange.Added('Faktor', 'Integer', '', '2')], TNewParameterMode.Overload);
  Hilfe := Applied(Outcome, BasisFile);
  Assert.Contains(Hilfe, 'function Doppelt(A: Integer; Faktor: Integer): Integer; overload;'#10'begin');
  Assert.Contains(Hilfe, 'function Doppelt(A: Integer): Integer; overload;'#10'begin'#10 +
    '  Result := Doppelt(A, 2);'#10'end;');
  Assert.Contains(Hilfe, '  Doppelt(3);');
  AssertParses(Outcome);
end;

procedure TLspChangeSignatureTests.OffersActionOnlyWhenEnabled;
var
  Resolver: TNameResolver;
  Tree: TSyntaxTree;
  Actions: TArray<TJSONObject>;
  Action: TJSONObject;
begin
  LoadProject;
  Resolver := TNameResolver.Create(FIndex);
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    Actions := TLspChangeSignature.Actions(True, Resolver, Tree, HauptFile, 'file:///C:/P/Haupt.pas',
      PositionOf(UnitHaupt, 'Teile(6'));
    Assert.AreEqual(1, Integer(Length(Actions)));
    try
      Assert.AreEqual(TLspChangeSignature.ClientCommand, Actions[0].GetValue<string>('command.command'));
    finally
      for Action in Actions do
        Action.Free;
    end;
    Assert.AreEqual(0, Integer(Length(TLspChangeSignature.Actions(False, Resolver, Tree, HauptFile, 'x',
      PositionOf(UnitHaupt, 'Teile(6')))));
    // Auf einer Variablen gibt es die Aktion nicht.
    Assert.AreEqual(0, Integer(Length(TLspChangeSignature.Actions(True, Resolver, Tree, HauptFile, 'x',
      PositionOf(UnitHaupt, 'B: TBasis')))));
  finally
    Tree.Free;
    Resolver.Free;
  end;
end;

procedure TLspChangeSignatureTests.ReadsRequestJson;
var
  Value: TJSONValue;
  Request: TChangeSignatureRequest;
  Answer: TJSONObject;
  Outcome: TChangeSignatureOutcome;
begin
  Value := TJSONObject.ParseJSONValue('{"parameters": [{"origin": 1, "name": "B"}, {"origin": -1, "name": "C", ' +
    '"type": "Integer", "modifier": "const", "value": "0"}], "newParameter": "updateCallers"}');
  try
    Request := TLspChangeSignature.ReadRequest(Value, TNewParameterMode.Overload, True);
  finally
    Value.Free;
  end;
  Assert.AreEqual(2, Integer(Length(Request.Changes)));
  Assert.AreEqual(1, Request.Changes[0].Origin);
  Assert.AreEqual('const', Request.Changes[1].Modifier);
  Assert.AreEqual(Ord(TNewParameterMode.UpdateCallers), Ord(Request.Mode));
  Assert.IsTrue(Request.VirtualOverload);
  Outcome := Default(TChangeSignatureOutcome);
  Outcome.Warnings := ['W'];
  Answer := TLspChangeSignature.OutcomeToJson(Outcome);
  try
    Assert.AreEqual('overload', Answer.GetValue<string>('newParameter'));
    Assert.IsNotNull(Answer.GetValue('edit'));
  finally
    Answer.Free;
  end;
end;

end.
