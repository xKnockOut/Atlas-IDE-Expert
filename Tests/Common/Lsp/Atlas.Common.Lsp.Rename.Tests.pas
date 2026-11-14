unit Atlas.Common.Lsp.Rename.Tests;

// Tests für das Umbenennen im Projekt (#30); Typkommentare wandern mit (#1838).

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Rename;

type
  [TestFixture]
  TLspRenameTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function CheckAt(const AMarker: string; const AFiles: TArray<string>): TRenameCheck;
    function EditsAt(const AMarker, ANewName: string): TArray<TRenameEdit>;
    function KundeError(const AMarker, ANewName: string): string;
    function FormEdits(const AMarker, ANewName: string; AHandlers: Boolean): TArray<TRenameEdit>; overload;
    function FormEdits(const AMarker, ANewName: string; AHandlers: Boolean;
      AFmx: Boolean): TArray<TRenameEdit>; overload;
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
    [Test]
    procedure RenamesHandlerMethodInFmxViews;
    [Test]
    procedure RejectsParameterThatWouldHideField;
    [Test]
    procedure RejectsFieldThatWouldBeHiddenByLocal;
    [Test]
    procedure AllowsRenameWithoutShadowing;
    [Test]
    procedure RenamesTypeComments;
    [Test]
    procedure KeepsTypeCommentsWhenOff;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.References;

const
  cWerkzeugFile = 'C:\P\Werkzeug.pas';
  cWerkzeugDfm = 'C:\P\Werkzeug.dfm';
  cHauptFile = 'C:\P\Haupt.pas';

  cUnitWerkzeug =
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

  cFormWerkzeug =
    'object Rechner: TRechner'#10 +
    '  OnSumme = Summe'#10 +
    '  object Summe: TButton'#10 +
    '    Caption = ''Summe'''#10 +
    '  end'#10 +
    'end';

  cUnitHaupt =
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

  cMaskeFile = 'C:\P\Maske.pas';
  cMaskeDfm = 'C:\P\Maske.dfm';
  cMaskeFmx = 'C:\P\Maske.fmx';
  cMaskeWindowsFmx = 'C:\P\Maske.Windows.fmx';

  cUnitMaske =
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

  cFormMaske =
    'object Maske: TMaske'#10 +
    '  object Button1: TButton'#10 +
    '    OnClick = Button1Click'#10 +
    '    OnEnter = Eigen'#10 +
    '  end'#10 +
    'end';

  cKundeFile = 'C:\P\Kunde.pas';

  // Feld und Parameter bzw. lokale Variable mit gleichem Namen.
  cUnitKunde =
    'unit Kunde;'#10 +                               // 0
    'interface'#10 +                                 // 1
    'type'#10 +                                      // 2
    '  TKunde = class'#10 +                          // 3
    '    Name: string;'#10 +                         // 4
    '    Wert: Integer;'#10 +                        // 5
    '    procedure SetzeName(const Name: string);'#10 + // 6
    '    procedure Zaehle;'#10 +                     // 7
    '    procedure Umbenennen(const AName: string);'#10 + // 8
    '  end;'#10 +                                    // 9
    'implementation'#10 +                            // 10
    'procedure TKunde.SetzeName(const Name: string);'#10 + // 11
    'begin'#10 +                                     // 12
    '  Self.Name := Name; // K1'#10 +                // 13
    'end;'#10 +                                      // 14
    'procedure TKunde.Zaehle;'#10 +                  // 15
    'var'#10 +                                       // 16
    '  Anzahl: Integer;'#10 +                        // 17
    'begin'#10 +                                     // 18
    '  Anzahl := Wert; // K2'#10 +                   // 19
    'end;'#10 +                                      // 20
    'procedure TKunde.Umbenennen(const AName: string);'#10 + // 21
    'begin'#10 +                                     // 22
    '  Wert := Length(AName); // K3'#10 +            // 23
    '  Name := ''x'';'#10 +                          // 24
    'end;'#10 +                                      // 25
    'end.';

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

{ TLspRenameTests }

procedure TLspRenameTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitWerkzeug, cWerkzeugFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspRenameTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspRenameTests.CheckAt(const AMarker: string; const AFiles: TArray<string>): TRenameCheck;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cUnitHaupt);
  try
    Result := TLspRename.Check(FResolver, FIndex, mTree, cHauptFile, PositionOf(cUnitHaupt, AMarker), AFiles);
  finally
    mTree.Free;
  end;
end;

function TLspRenameTests.EditsAt(const AMarker, ANewName: string): TArray<TRenameEdit>;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cUnitHaupt);
  try
    Result := TLspRename.Edits(FResolver, FIndex, mTree, TReferenceSearch.Create(cHauptFile,
      PositionOf(cUnitHaupt, AMarker), True, [cWerkzeugFile, cHauptFile],
      function(const AFileName: string; out AText: string): Boolean
      begin
        Result := True;
        if SameText(AFileName, cWerkzeugFile) then
        begin
          AText := cUnitWerkzeug;
        end
        else if SameText(AFileName, cWerkzeugDfm) then
        begin
          AText := cFormWerkzeug;
        end
        else
        begin
          Result := False;
        end;
      end), ANewName);
  finally
    mTree.Free;
  end;
end;

function TLspRenameTests.KundeError(const AMarker, ANewName: string): string;
var
  mIndex: ISymbolIndex;
  mResolver: TNameResolver;
  mTree: TSyntaxTree;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cUnitKunde, cKundeFile, nil));
  mResolver := TNameResolver.Create(mIndex);
  mTree := TPascalParser.Parse(cUnitKunde);
  try
    Result := '';
    try
      TLspRename.Edits(mResolver, mIndex, mTree, TReferenceSearch.Create(cKundeFile, PositionOf(cUnitKunde, AMarker),
        True, [cKundeFile],
        function(const AFileName: string; out AText: string): Boolean
        begin
          Result := SameText(AFileName, cKundeFile);
          if Result then
          begin
            AText := cUnitKunde;
          end;
        end), ANewName);
    except
      on E: EJsonRpcError do
        Result := E.Message;
    end;
  finally
    mTree.Free;
    mResolver.Free;
  end;
end;

function TLspRenameTests.FormEdits(const AMarker, ANewName: string; AHandlers: Boolean): TArray<TRenameEdit>;
begin
  Result := FormEdits(AMarker, ANewName, AHandlers, False);
end;

function TLspRenameTests.FormEdits(const AMarker, ANewName: string; AHandlers: Boolean;

  AFmx: Boolean): TArray<TRenameEdit>;
var
  mIndex: ISymbolIndex;
  mResolver: TNameResolver;
  mTree: TSyntaxTree;
  mUnitText: string;
begin
  // FMX (#87): Formular und Plattformansicht über die {$R}-Direktiven der Unit.
  mUnitText := cUnitMaske;
  if AFmx then
  begin
    mUnitText := StringReplace(mUnitText, 'implementation'#10,
      'implementation'#10'{$R *.fmx}'#10'{$R *.Windows.fmx MSWINDOWS}'#10, []);
  end;
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(mUnitText, cMaskeFile, nil));
  mResolver := TNameResolver.Create(mIndex);
  mTree := TPascalParser.Parse(mUnitText);
  try
    Result := TLspRename.Edits(mResolver, mIndex, mTree, TReferenceSearch.Create(cMaskeFile,
      PositionOf(mUnitText, AMarker), True, [cMaskeFile],
      function(const AFileName: string; out AText: string): Boolean
      begin
        Result := True;
        if SameText(AFileName, cMaskeFile) then
        begin
          AText := mUnitText;
        end
        else if not AFmx and SameText(AFileName, cMaskeDfm) then
        begin
          AText := cFormMaske;
        end
        else if AFmx and (SameText(AFileName, cMaskeFmx) or SameText(AFileName, cMaskeWindowsFmx)) then
        begin
          AText := cFormMaske;
        end
        else
        begin
          Result := False;
        end;
      end), TRenameRequest.Create(ANewName, AHandlers, TReferenceSettings.SureOnly, nil));
  finally
    mTree.Free;
    mResolver.Free;
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
  mChecked: TRenameCheck;
begin
  mChecked := CheckAt('Summe(1', [cWerkzeugFile]);
  Assert.AreEqual('', mChecked.Error);
  Assert.AreEqual('Summe', mChecked.Name);
  Assert.AreEqual(8, mChecked.Range.StartPos.Line);
  Assert.AreEqual(4, mChecked.Range.StartPos.Character);
  Assert.AreEqual(9, mChecked.Range.EndPos.Character);
end;

procedure TLspRenameTests.RejectsSymbolsOutsideProject;
begin
  // Werkzeug.pas gehört hier nicht zum Projekt, wie eine Bibliotheks-Unit.
  Assert.IsTrue(Pos('außerhalb des Projekts', CheckAt('Summe(1', []).Error) > 0);
  Assert.AreNotEqual('', CheckAt('begin', [cWerkzeugFile]).Error);
end;

procedure TLspRenameTests.RejectsUnitNames;
begin
  Assert.IsTrue(Pos('Dateinamen', CheckAt('Werkzeug;', [cWerkzeugFile]).Error) > 0);
end;

procedure TLspRenameTests.RenamesAcrossUnitsAndForm;
var
  mFound: TArray<TRenameEdit>;
  mEdit: TRenameEdit;
  mHaupt, mWerkzeug, mForm: Integer;
begin
  mFound := EditsAt('Summe(1', 'Addiere');
  mHaupt := 0;
  mWerkzeug := 0;
  mForm := 0;
  for mEdit in mFound do
  begin
    if SameText(mEdit.FileName, cHauptFile) then
    begin
      Inc(mHaupt);
    end
    else if SameText(mEdit.FileName, cWerkzeugFile) then
    begin
      Inc(mWerkzeug);
    end
    else if SameText(mEdit.FileName, cWerkzeugDfm) then
    begin
      Inc(mForm);
    end;
  end;
  Assert.AreEqual(3, mHaupt);
  Assert.AreEqual(2, mWerkzeug);
  Assert.AreEqual(2, mForm);
end;

procedure TLspRenameTests.RejectsInvalidNewName;
var
  mRaised: Boolean;
begin
  mRaised := False;
  try
    EditsAt('Summe(1', 'end');
  except
    on EJsonRpcError do
      mRaised := True;
  end;
  Assert.IsTrue(mRaised);
end;

procedure TLspRenameTests.RenamesComponentWithHandlers;
var
  mFound: TArray<TRenameEdit>;
  mEdit: TRenameEdit;
  mField, mHandler, mOther: Integer;
begin
  mFound := FormEdits('Button1: TObject', 'btnSpeichern', True);
  mField := 0;
  mHandler := 0;
  mOther := 0;
  for mEdit in mFound do
  begin
    if mEdit.NewText = 'btnSpeichern' then
    begin
      Inc(mField);
    end
    else if mEdit.NewText = 'btnSpeichernClick' then
    begin
      Inc(mHandler);
    end
    else
    begin
      Inc(mOther);
    end;
  end;
  // Feld, Verwendung im Code und Objektname in der DFM.
  Assert.AreEqual(3, mField);
  // Deklaration, Implementierung und Zuordnung in der DFM; Eigen bleibt.
  Assert.AreEqual(3, mHandler);
  Assert.AreEqual(0, mOther);
end;

procedure TLspRenameTests.KeepsHandlersWhenDisabled;
var
  mEdit: TRenameEdit;
begin
  for mEdit in FormEdits('Button1: TObject', 'btnSpeichern', False) do
  begin
    Assert.AreEqual('btnSpeichern', mEdit.NewText);
  end;
end;

procedure TLspRenameTests.RenamesHandlersInFmxViews;
var
  mEdit: TRenameEdit;
  mFmx, mWindows: Integer;
begin
  mFmx := 0;
  mWindows := 0;
  for mEdit in FormEdits('Button1: TObject', 'btnSpeichern', True, True) do
  begin
    if SameText(mEdit.FileName, cMaskeFmx) then
    begin
      Inc(mFmx);
    end
    else if SameText(mEdit.FileName, cMaskeWindowsFmx) then
    begin
      Inc(mWindows);
    end;
  end;
  // Objektname und Zuordnung OnClick in beiden Formularen.
  Assert.AreEqual(2, mFmx);
  Assert.AreEqual(2, mWindows);
end;

procedure TLspRenameTests.RenamesHandlerMethodInFmxViews;
var
  mEdit: TRenameEdit;
  mFmx, mWindows: Integer;
begin
  // Abnahme #87: Umbenennen von Button1Click ändert die Zuordnung in Maske.fmx und Maske.Windows.fmx.
  mFmx := 0;
  mWindows := 0;
  for mEdit in FormEdits('Button1Click(Sender', 'Speichern', False, True) do
  begin
    if SameText(mEdit.FileName, cMaskeFmx) then
    begin
      Inc(mFmx);
      Assert.AreEqual('Speichern', mEdit.NewText);
    end
    else if SameText(mEdit.FileName, cMaskeWindowsFmx) then
    begin
      Inc(mWindows);
      Assert.AreEqual('Speichern', mEdit.NewText);
    end
    else
    begin
      Assert.AreEqual(cMaskeFile, mEdit.FileName, 'nur Unit und Formulare');
    end;
  end;
  Assert.AreEqual(1, mFmx);
  Assert.AreEqual(1, mWindows);
end;

procedure TLspRenameTests.RejectsParameterThatWouldHideField;
var
  mError: string;
begin
  // AName -> Name: "Name := 'x'" meinte danach den Parameter statt des Feldes.
  mError := KundeError('AName); // K3', 'Name');
  Assert.IsTrue(Pos('Bedeutung', mError) > 0, mError);
  Assert.IsTrue(Pos('Zeile 25', mError) > 0, mError);
  Assert.IsTrue(Pos('Feld TKunde.Name', mError) > 0, mError);
end;

procedure TLspRenameTests.RejectsFieldThatWouldBeHiddenByLocal;
var
  mError: string;
begin
  // Feld Wert -> Anzahl: In Zaehle verdeckt die lokale Variable Anzahl das umbenannte Feld.
  mError := KundeError('Wert: Integer', 'Anzahl');
  Assert.IsTrue(Pos('Zeile 20', mError) > 0, mError);
  Assert.IsTrue(Pos('lokale Variable Anzahl', mError) > 0, mError);
  mError := KundeError('Wert; // K2', 'Anzahl');
  Assert.IsTrue(Pos('lokale Variable Anzahl', mError) > 0, mError);
end;

procedure TLspRenameTests.AllowsRenameWithoutShadowing;
begin
  // Das Feld ist in SetzeName nur über Self.Name erreichbar; Wert kommt dort nicht vor.
  Assert.AreEqual('', KundeError('Name; // K1', 'Wert'));
  Assert.AreEqual('', KundeError('AName); // K3', 'Text'));
  // Nur Groß- und Kleinschreibung.
  Assert.AreEqual('', KundeError('AName); // K3', 'aname'));
  // Lokaler Name über einem Feld: Das Feld bleibt über Self erreichbar und wird nirgends ohne Self benutzt.
  Assert.AreEqual('', KundeError('Anzahl := Wert', 'Zaehler'));
end;

const
  cKopfFile = 'C:\P\Kopf.pas';

  cUnitKopf =
    'unit Kopf;'#10 +                                // 0
    'interface'#10 +                                 // 1
    'type'#10 +                                      // 2
    '  TKunde = class'#10 +                          // 3
    '    procedure Lauf;'#10 +                       // 4
    '    procedure Halt;'#10 +                       // 5
    '  end;'#10 +                                    // 6
    'implementation'#10 +                            // 7
    #10 +                                            // 8
    '{ TKunde }'#10 +                                // 9
    #10 +                                            // 10
    'procedure TKunde.Lauf;'#10 +                    // 11
    'begin'#10 +                                     // 12
    'end;'#10 +                                      // 13
    #10 +                                            // 14
    '// TKunde ist hier gemeint.'#10 +               // 15
    '(* TKunde *)'#10 +                              // 16
    'procedure TKunde.Halt;'#10 +                    // 17
    'begin'#10 +                                     // 18
    'end;'#10 +                                      // 19
    #10 +                                            // 20
    '// TKunde'#10 +                                 // 21
    'procedure Frei;'#10 +                           // 22
    'begin'#10 +                                     // 23
    'end;'#10 +                                      // 24
    'end.';

function KopfEdits(ATypeComments: Boolean): TArray<TRenameEdit>;
var
  mIndex: ISymbolIndex;
  mResolver: TNameResolver;
  mTree: TSyntaxTree;
  mRequest: TRenameRequest;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cUnitKopf, cKopfFile, nil));
  mResolver := TNameResolver.Create(mIndex);
  mTree := TPascalParser.Parse(cUnitKopf);
  try
    mRequest := TRenameRequest.Create('TCustomer');
    mRequest.TypeComments := ATypeComments;
    Result := TLspRename.Edits(mResolver, mIndex, mTree, TReferenceSearch.Create(cKopfFile,
      PositionOf(cUnitKopf, 'TKunde = class'), True, [cKopfFile],
      function(const AFileName: string; out AText: string): Boolean
      begin
        Result := SameText(AFileName, cKopfFile);
        if Result then
        begin
          AText := cUnitKopf;
        end;
      end), mRequest);
  finally
    mTree.Free;
    mResolver.Free;
  end;
end;

function EditOnLine(const AEdits: TArray<TRenameEdit>; ALine: Integer; out AEdit: TRenameEdit): Boolean;
var
  mEdit: TRenameEdit;
begin
  for mEdit in AEdits do
  begin
    if mEdit.Range.StartPos.Line = ALine then
    begin
      AEdit := mEdit;
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TLspRenameTests.RenamesTypeComments;
var
  mFound: TArray<TRenameEdit>;
  mEdit: TRenameEdit;
begin
  mFound := KopfEdits(True);
  Assert.IsTrue(EditOnLine(mFound, 9, mEdit), '{ TKunde } über den Rümpfen');
  Assert.AreEqual(2, mEdit.Range.StartPos.Character);
  Assert.AreEqual(8, mEdit.Range.EndPos.Character);
  Assert.AreEqual('TCustomer', mEdit.NewText);
  Assert.IsTrue(EditOnLine(mFound, 16, mEdit), '(* TKunde *) direkt über dem Rumpf');
  Assert.AreEqual(3, mEdit.Range.StartPos.Character);
  Assert.IsFalse(EditOnLine(mFound, 15, mEdit), 'Kommentar mit anderem Text bleibt');
  Assert.IsFalse(EditOnLine(mFound, 21, mEdit), 'über einer freien Routine bleibt');
  Assert.IsTrue(EditOnLine(mFound, 11, mEdit), 'Rumpf wie bisher');
end;

procedure TLspRenameTests.KeepsTypeCommentsWhenOff;
var
  mFound: TArray<TRenameEdit>;
  mEdit: TRenameEdit;
begin
  mFound := KopfEdits(False);
  Assert.IsFalse(EditOnLine(mFound, 9, mEdit), 'classCompletion.typeComment = off: Kommentar bleibt');
  Assert.IsTrue(EditOnLine(mFound, 11, mEdit));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspRenameTests);

end.
