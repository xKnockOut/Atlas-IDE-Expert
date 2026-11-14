unit Atlas.Common.Lsp.ChangeSignature.Tests;

// Tests für „Signatur ändern“ im Projekt (#100): Überschreibungen, Interfaces,
// Aufrufer in anderen Units, gebundene Handler, Abbruch- und Warnfälle.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Lsp.ChangeSignature,
  Atlas.Common.Lsp.ChangeSignature.Collector;

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
    function SourceAt(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition): TChangeSignatureSource;
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
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.Rename;

const
  cBasisFile = 'C:\P\Basis.pas';
  cHauptFile = 'C:\P\Haupt.pas';
  cMaskeFile = 'C:\P\Maske.pas';
  cMaskeDfm = 'C:\P\Maske.dfm';
  cKlassenFile = 'C:\Lib\Klassen.pas';

  cUnitBasis =
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

  cUnitHaupt =
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

  cUnitKlassen =
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

  cUnitMaske =
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

  cFormMaske =
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
  mIndex, mLine, mLineStart, I: Integer;
begin
  mIndex := Pos(AMarker, AText);
  if mIndex = 0 then
  begin
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
  end;
  mLine := 0;
  mLineStart := 1;
  for I := 1 to mIndex - 1 do
  begin
    if AText[I] = #10 then
    begin
      Inc(mLine);
      mLineStart := I + 1;
    end;
  end;
  Result := TTextPosition.Create(mLine, mIndex - mLineStart);
end;

function Count(const AText, APart: string): Integer;
var
  mOffset: Integer;
begin
  Result := 0;
  mOffset := PosEx(APart, AText, 1);
  while mOffset > 0 do
  begin
    Inc(Result);
    mOffset := PosEx(APart, AText, mOffset + 1);
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
  begin
    FIndex.AddUnit(TIndexExtractor.ExtractText(AText, AFileName, nil));
  end;
end;

function TLspChangeSignatureTests.TextOf(const AFileName: string): string;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FFiles) do
  begin
    if SameText(FFiles[mIndex], AFileName) then
    begin
      Exit(FTexts[mIndex]);
    end;
  end;
  Result := '';
end;

procedure TLspChangeSignatureTests.LoadProject;
begin
  AddFile(cBasisFile, cUnitBasis);
  AddFile(cHauptFile, cUnitHaupt);
end;

function TLspChangeSignatureTests.SourceAt(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): TChangeSignatureSource;
begin
  Result := Default(TChangeSignatureSource);
  Result.Resolver := AResolver;
  Result.Index := FIndex;
  Result.Tree := ATree;
  Result.FileName := AFileName;
  Result.Position := APosition;
  Result.Files := [cBasisFile, cHauptFile, cMaskeFile, cMaskeDfm];
  Result.ReadText :=
    function(const AName: string; out AText: string): Boolean
    begin
      AText := TextOf(AName);
      Result := AText <> '';
    end;
end;

function TLspChangeSignatureTests.Info(const AFileName, AMarker: string): TChangeSignatureInfo;
var
  mResolver: TNameResolver;
  mTree: TSyntaxTree;
  mText: string;
begin
  mText := TextOf(AFileName);
  mResolver := TNameResolver.Create(FIndex);
  mTree := TPascalParser.Parse(mText);
  try
    Result := TLspChangeSignature.Prepare(SourceAt(mResolver, mTree, AFileName, PositionOf(mText, AMarker)));
  finally
    mTree.Free;
    mResolver.Free;
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
  mResolver: TNameResolver;
  mTree: TSyntaxTree;
  mText: string;
  mRequest: TChangeSignatureRequest;
begin
  mText := TextOf(AFileName);
  mRequest.Changes := AChanges;
  mRequest.Mode := AMode;
  mRequest.VirtualOverload := AVirtual;
  mResolver := TNameResolver.Create(FIndex);
  mTree := TPascalParser.Parse(mText);
  try
    Result := TLspChangeSignature.Execute(SourceAt(mResolver, mTree, AFileName, PositionOf(mText, AMarker)), mRequest,
      function(const AName: string): Boolean
      begin
        Result := SameText(AName, FReadOnly);
      end);
  finally
    mTree.Free;
    mResolver.Free;
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
  mEdits: TArray<TTextEdit>;
  mEdit: TRenameEdit;
begin
  mEdits := nil;
  for mEdit in AOutcome.Edits do
  begin
    if SameText(mEdit.FileName, AFileName) then
    begin
      mEdits := mEdits + [TTextEdit.Create(mEdit.Range, mEdit.NewText)];
    end;
  end;
  Result := TChangeSignature.ApplyEdits(TextOf(AFileName), mEdits);
end;

procedure TLspChangeSignatureTests.AssertParses(const AOutcome: TChangeSignatureOutcome);
var
  mTree: TSyntaxTree;
  mFileName: string;
begin
  for mFileName in [cBasisFile, cHauptFile, cMaskeFile] do
  begin
    if TextOf(mFileName) = '' then
    begin
      Continue;
    end;
    mTree := TPascalParser.Parse(Applied(AOutcome, mFileName));
    try
      Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)), mFileName);
    finally
      mTree.Free;
    end;
  end;
end;

procedure TLspChangeSignatureTests.PrepareListsParametersAndMembers;
var
  mFound: TChangeSignatureInfo;
begin
  LoadProject;
  mFound := Info(cBasisFile, 'Zeige(const Text: string; Anzahl: Integer); override');
  Assert.AreEqual('Zeige', mFound.Name);
  Assert.AreEqual('TBasis', mFound.Container);
  Assert.AreEqual('procedure', mFound.Keyword);
  Assert.AreEqual(2, Integer(Length(mFound.Parameters)));
  Assert.AreEqual('const', mFound.Parameters[0].Modifier);
  // Deklaration in TBasis und die Überschreibung in TKind.
  Assert.AreEqual(2, mFound.Members);
  Assert.IsFalse(mFound.InterfaceMethod);
end;

procedure TLspChangeSignatureTests.OverloadKeepsOldSignature;
var
  mOutcome: TChangeSignatureOutcome;
  mBasis: string;
begin
  LoadProject;
  mOutcome := Run(cBasisFile, 'Zeige(const Text: string; Anzahl: Integer); virtual', [TParameterChange.Kept(0, 'Text'),
    TParameterChange.Kept(1, 'Anzahl'), TParameterChange.Added('Farbe', 'Integer', '', 'clBlack')],
    TNewParameterMode.Overload);
  Assert.AreEqual(Ord(TNewParameterMode.Overload), Ord(mOutcome.Mode));
  mBasis := Applied(mOutcome, cBasisFile);
  Assert.Contains(mBasis, '    procedure Zeige(const Text: string; Anzahl: Integer; Farbe: Integer); overload; virtual;'#10 +
    '    procedure Zeige(const Text: string; Anzahl: Integer); overload;'#10);
  Assert.Contains(mBasis, 'procedure Zeige(const Text: string; Anzahl: Integer; Farbe: Integer); overload; override;');
  Assert.Contains(mBasis, 'procedure TBasis.Zeige(const Text: string; Anzahl: Integer; Farbe: Integer);'#10'begin');
  Assert.Contains(mBasis, 'procedure TBasis.Zeige(const Text: string; Anzahl: Integer);'#10'begin'#10 +
    '  Zeige(Text, Anzahl, clBlack);'#10'end;');
  // Die Überschreibung reicht den neuen Parameter weiter, statt sich über die alte Überladung selbst aufzurufen.
  Assert.Contains(mBasis, '  inherited Zeige(Text, Anzahl, Farbe);');
  Assert.AreEqual(cUnitHaupt, Applied(mOutcome, cHauptFile));
  Assert.AreEqual(0, Count(mBasis, 'Farbe: Integer ='));
  AssertParses(mOutcome);
end;

procedure TLspChangeSignatureTests.VirtualOverloadOnRequest;
var
  mOutcome: TChangeSignatureOutcome;
begin
  LoadProject;
  mOutcome := Run(cBasisFile, 'Zeige(const Text: string; Anzahl: Integer); virtual', [TParameterChange.Kept(0, 'Text'),
    TParameterChange.Kept(1, 'Anzahl'), TParameterChange.Added('Farbe', 'Integer', '', '0')],
    TNewParameterMode.Overload, True);
  Assert.Contains(Applied(mOutcome, cBasisFile), 'procedure Zeige(const Text: string; Anzahl: Integer); overload; virtual;');
end;

procedure TLspChangeSignatureTests.UpdateCallersPassesValue;
var
  mOutcome: TChangeSignatureOutcome;
  mBasis, mHaupt: string;
begin
  LoadProject;
  mOutcome := Run(cBasisFile, 'Zeige(const Text: string; Anzahl: Integer); virtual', [TParameterChange.Kept(0, 'Text'),
    TParameterChange.Kept(1, 'Anzahl'), TParameterChange.Added('Farbe', 'Integer', '', '0')],
    TNewParameterMode.UpdateCallers);
  mBasis := Applied(mOutcome, cBasisFile);
  mHaupt := Applied(mOutcome, cHauptFile);
  Assert.Contains(mHaupt, 'B.Zeige(''x'', 1, 0);');
  Assert.Contains(mHaupt, 'K.Zeige(''y'', 2, 0);');
  Assert.Contains(mBasis, '  inherited Zeige(Text, Anzahl, Farbe);');
  Assert.AreEqual(0, Count(mBasis, 'overload'));
  Assert.AreEqual(4, Count(mBasis, 'Anzahl: Integer; Farbe: Integer)'));
  AssertParses(mOutcome);
end;

procedure TLspChangeSignatureTests.ReorderChangesCallersInAllUnits;
var
  mOutcome: TChangeSignatureOutcome;
  mHaupt: string;
begin
  LoadProject;
  mOutcome := Run(cHauptFile, 'Teile(6', [TParameterChange.Kept(1, 'B'), TParameterChange.Kept(0, 'A')],
    TNewParameterMode.Overload);
  mHaupt := Applied(mOutcome, cHauptFile);
  Assert.Contains(mHaupt, 'B.Teile(2, 6);');
  Assert.Contains(mHaupt, 'B.Teile(2, B.Teile(4, 8));');
  Assert.Contains(Applied(mOutcome, cBasisFile), 'function TBasis.Teile(B, A: Integer): Integer;');
  Assert.Contains(Applied(mOutcome, cBasisFile), '    function Teile(B, A: Integer): Integer;');
  AssertParses(mOutcome);
end;

procedure TLspChangeSignatureTests.RemovesUnusedParameter;
var
  mOutcome: TChangeSignatureOutcome;
begin
  LoadProject;
  mOutcome := Run(cBasisFile, 'Leer(A: Integer; B: Integer);'#10'  end', [TParameterChange.Kept(1, 'B')],
    TNewParameterMode.Overload);
  Assert.Contains(Applied(mOutcome, cHauptFile), 'B.Leer(2);');
  Assert.Contains(Applied(mOutcome, cBasisFile), 'procedure TBasis.Leer(B: Integer);');
  AssertParses(mOutcome);
end;

procedure TLspChangeSignatureTests.RejectsRemovingUsedParameter;
begin
  LoadProject;
  Assert.Contains(Error(cBasisFile, 'Teile(A, B: Integer): Integer;'#10'    procedure', [TParameterChange.Kept(0, 'A')]),
    'Zeile 26');
end;

procedure TLspChangeSignatureTests.RenamesParameterEverywhere;
var
  mOutcome: TChangeSignatureOutcome;
  mBasis: string;
begin
  LoadProject;
  mOutcome := Run(cBasisFile, 'Zeige(const Text: string; Anzahl: Integer); virtual', [TParameterChange.Kept(0, 'Text'),
    TParameterChange.Kept(1, 'Menge')], TNewParameterMode.Overload);
  mBasis := Applied(mOutcome, cBasisFile);
  Assert.Contains(mBasis, '/// <param name="Menge">Wie oft</param>');
  Assert.Contains(mBasis, '  Writeln(Text, Menge);');
  Assert.Contains(mBasis, '  inherited Zeige(Text, Menge);');
  Assert.AreEqual(0, Count(mBasis, 'Anzahl'));
  Assert.AreEqual(cUnitHaupt, Applied(mOutcome, cHauptFile));
  AssertParses(mOutcome);
end;

procedure TLspChangeSignatureTests.InterfaceForcesUpdateCallers;
var
  mOutcome: TChangeSignatureOutcome;
  mBasis: string;
begin
  LoadProject;
  Assert.IsTrue(Info(cBasisFile, 'Summe(A, B: Integer): Integer;'#10'  end;'#10'  TBasis').InterfaceMethod);
  mOutcome := Run(cBasisFile, 'Summe(A, B: Integer): Integer;'#10'  end;'#10'  TBasis', [TParameterChange.Kept(0, 'A'),
    TParameterChange.Kept(1, 'B'), TParameterChange.Added('C', 'Integer', '', '0')], TNewParameterMode.Overload);
  Assert.AreEqual(Ord(TNewParameterMode.UpdateCallers), Ord(mOutcome.Mode));
  mBasis := Applied(mOutcome, cBasisFile);
  Assert.AreEqual(3, Count(mBasis, 'Summe(A, B: Integer; C: Integer): Integer;'));
  Assert.Contains(Applied(mOutcome, cHauptFile), 'R.Summe(1, 2, 0);');
  Assert.AreEqual(0, Count(mBasis, 'overload'));
  AssertParses(mOutcome);
end;

procedure TLspChangeSignatureTests.StartsFromOverrideOrCall;
begin
  LoadProject;
  // Von der Überschreibung, vom Rumpf und vom Aufruf aus dieselbe Kette.
  Assert.AreEqual('TBasis', Info(cBasisFile, 'Zeige(const Text: string; Anzahl: Integer); override').Container);
  Assert.AreEqual('TBasis', Info(cBasisFile, 'Zeige(Text, Anzahl);').Container);
  Assert.AreEqual(2, Info(cHauptFile, 'Zeige(''y''').Members);
end;

procedure TLspChangeSignatureTests.RejectsLibraryEventHandler;
var
  mOutcome: TChangeSignatureOutcome;
  mFound: TChangeSignatureInfo;
begin
  AddFile(cKlassenFile, cUnitKlassen);
  AddFile(cMaskeFile, cUnitMaske);
  AddFile(cMaskeDfm, cFormMaske);
  mFound := Info(cMaskeFile, 'Button1Click(Sender: TObject);'#10'    procedure');
  Assert.AreEqual('TNotifyEvent', mFound.BoundEvent);
  Assert.IsTrue(mFound.EventFixed);
  Assert.Contains(Error(cMaskeFile, 'Button1Click(Sender: TObject);'#10'    procedure',
    [TParameterChange.Kept(0, 'Sender'), TParameterChange.Added('X', 'Integer', '', '0')]), 'TNotifyEvent');
  // Umbenennen bleibt möglich.
  mOutcome := Run(cMaskeFile, 'Button1Click(Sender: TObject);'#10'    procedure', [TParameterChange.Kept(0, 'Quelle')],
    TNewParameterMode.Overload);
  Assert.Contains(Applied(mOutcome, cMaskeFile), 'procedure TMaske.Button1Click(Quelle: TObject);');
end;

procedure TLspChangeSignatureTests.ChangesProjectEventType;
var
  mOutcome: TChangeSignatureOutcome;
  mMaske: string;
begin
  AddFile(cKlassenFile, cUnitKlassen);
  AddFile(cMaskeFile, cUnitMaske);
  AddFile(cMaskeDfm, cFormMaske);
  mOutcome := Run(cMaskeFile, 'BoxWert(Sender: TObject; Wert: Integer);'#10'  end', [TParameterChange.Kept(0, 'Sender'),
    TParameterChange.Kept(1, 'Wert'), TParameterChange.Added('Alt', 'Integer', '', '0')], TNewParameterMode.Overload);
  // Gebundener Handler: keine Überladung, der Ereignistyp ändert sich mit.
  Assert.AreEqual(Ord(TNewParameterMode.UpdateCallers), Ord(mOutcome.Mode));
  mMaske := Applied(mOutcome, cMaskeFile);
  Assert.Contains(mMaske, 'TWertEvent = procedure(Sender: TObject; Wert: Integer; Alt: Integer) of object;');
  Assert.Contains(mMaske, 'procedure TMaske.BoxWert(Sender: TObject; Wert: Integer; Alt: Integer);');
  Assert.IsTrue(Length(mOutcome.Warnings) > 0);
  AssertParses(mOutcome);
end;

procedure TLspChangeSignatureTests.RejectsCollidingOverload;
var
  mText: string;
begin
  mText := StringReplace(cUnitBasis, '    function Teile(A, B: Integer): Integer;'#10,
    '    function Teile(A, B: Integer): Integer; overload;'#10 +
    '    function Teile(A, B, C: Integer): Integer; overload;'#10, []);
  AddFile(cBasisFile, mText);
  AddFile(cHauptFile, cUnitHaupt);
  Assert.Contains(Error(cBasisFile, 'Teile(A, B: Integer): Integer; overload', [TParameterChange.Kept(0, 'A'),
    TParameterChange.Kept(1, 'B'), TParameterChange.Added('C', 'Integer', '', '0')]), 'kollidiert');
end;

procedure TLspChangeSignatureTests.WarnsAboutPointersAndReadOnlyCallers;
var
  mOutcome: TChangeSignatureOutcome;
  mText: string;
begin
  mText := StringReplace(cUnitHaupt, '  R.Summe(1, 2);'#10, '  R.Summe(1, 2);'#10'  P := @B.Teile;'#10, []);
  AddFile(cBasisFile, cUnitBasis);
  AddFile(cHauptFile, mText);
  FReadOnly := cHauptFile;
  mOutcome := Run(cBasisFile, 'Teile(A, B: Integer): Integer;'#10'    procedure', [TParameterChange.Kept(1, 'B'),
    TParameterChange.Kept(0, 'A')], TNewParameterMode.Overload);
  Assert.AreEqual(mText, Applied(mOutcome, cHauptFile));
  Assert.Contains(string.Join(#10, mOutcome.Warnings), 'Methodenzeiger');
  Assert.Contains(string.Join(#10, mOutcome.Warnings), 'Haupt.pas');
  // Die Deklaration selbst schreibgeschützt: Abbruch.
  FReadOnly := cBasisFile;
  Assert.Contains(Error(cBasisFile, 'Teile(A, B: Integer): Integer;'#10'    procedure', [TParameterChange.Kept(1, 'B'),
    TParameterChange.Kept(0, 'A')]), 'Basis.pas');
end;

procedure TLspChangeSignatureTests.RoutineWithoutDeclaration;
const
  cUnitHilfe =
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
  mOutcome: TChangeSignatureOutcome;
  mHilfe: string;
begin
  AddFile(cBasisFile, cUnitHilfe);
  mOutcome := Run(cBasisFile, 'Doppelt(A: Integer)', [TParameterChange.Kept(0, 'A'),
    TParameterChange.Added('Faktor', 'Integer', '', '2')], TNewParameterMode.Overload);
  mHilfe := Applied(mOutcome, cBasisFile);
  Assert.Contains(mHilfe, 'function Doppelt(A: Integer; Faktor: Integer): Integer; overload;'#10'begin');
  Assert.Contains(mHilfe, 'function Doppelt(A: Integer): Integer; overload;'#10'begin'#10 +
    '  Result := Doppelt(A, 2);'#10'end;');
  Assert.Contains(mHilfe, '  Doppelt(3);');
  AssertParses(mOutcome);
end;

procedure TLspChangeSignatureTests.OffersActionOnlyWhenEnabled;
var
  mResolver: TNameResolver;
  mTree: TSyntaxTree;
  mActions: TArray<TJSONObject>;
  mAction: TJSONObject;
begin
  LoadProject;
  mResolver := TNameResolver.Create(FIndex);
  mTree := TPascalParser.Parse(cUnitHaupt);
  try
    mActions := TLspChangeSignature.Actions(True, mResolver, mTree, cHauptFile, 'file:///C:/P/Haupt.pas',
      PositionOf(cUnitHaupt, 'Teile(6'));
    Assert.AreEqual(1, Integer(Length(mActions)));
    try
      Assert.AreEqual(TLspChangeSignature.cClientCommand, mActions[0].GetValue<string>('command.command'));
    finally
      for mAction in mActions do
      begin
        mAction.Free;
      end;
    end;
    Assert.AreEqual(0, Integer(Length(TLspChangeSignature.Actions(False, mResolver, mTree, cHauptFile, 'x',
      PositionOf(cUnitHaupt, 'Teile(6')))));
    // Auf einer Variablen gibt es die Aktion nicht.
    Assert.AreEqual(0, Integer(Length(TLspChangeSignature.Actions(True, mResolver, mTree, cHauptFile, 'x',
      PositionOf(cUnitHaupt, 'B: TBasis')))));
  finally
    mTree.Free;
    mResolver.Free;
  end;
end;

procedure TLspChangeSignatureTests.ReadsRequestJson;
var
  mValue: TJSONValue;
  mRequest: TChangeSignatureRequest;
  mAnswer: TJSONObject;
  mOutcome: TChangeSignatureOutcome;
begin
  mValue := TJSONObject.ParseJSONValue('{"parameters": [{"origin": 1, "name": "B"}, {"origin": -1, "name": "C", ' +
    '"type": "Integer", "modifier": "const", "value": "0"}], "newParameter": "updateCallers"}');
  try
    mRequest := TLspChangeSignature.ReadRequest(mValue, TNewParameterMode.Overload, True);
  finally
    mValue.Free;
  end;
  Assert.AreEqual(2, Integer(Length(mRequest.Changes)));
  Assert.AreEqual(1, mRequest.Changes[0].Origin);
  Assert.AreEqual('const', mRequest.Changes[1].Modifier);
  Assert.AreEqual(Ord(TNewParameterMode.UpdateCallers), Ord(mRequest.Mode));
  Assert.IsTrue(mRequest.VirtualOverload);
  mOutcome := Default(TChangeSignatureOutcome);
  mOutcome.Warnings := ['W'];
  mAnswer := TLspChangeSignature.OutcomeToJson(mOutcome);
  try
    Assert.AreEqual('overload', mAnswer.GetValue<string>('newParameter'));
    Assert.IsNotNull(mAnswer.GetValue('edit'));
  finally
    mAnswer.Free;
  end;
end;

end.
