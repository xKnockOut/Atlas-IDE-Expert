unit Atlas.Common.Editing.TestDrafts;

// Entwurf eines Testfalls für eine Methode oder Routine (#1226): Werte
// vorbereiten, die Methode aufrufen, Platzhalter-Prüfungen passend zum Typ.
// Ein Entwurf endet mit Assert.Fail, damit er nicht unbemerkt grün läuft.
// Mit Werten aus dem Debugger (#1873) entsteht daraus ein nachgestellter Fall:
// Literale statt Platzhalter, optional Assert.WillRaise statt Ergebnisprüfung.
// Dazu das Eintragen in eine vorhandene Testunit: Deklaration vor dem "end"
// der Testklasse, Rumpf vor initialization bzw. "end.", getestete Unit im uses.
// Reine Textfunktionen; Index, Dateien und Testunit liefert der Aufrufer.

interface

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.ChangeSignature;

type
  /// <summary>Ein Wert des Tests: Parameter der Methode oder Feld des Objekts.</summary>
  TTestDraftValue = record
    Name: string;
    /// <summary>'' bei untypisierten Parametern.</summary>
    TypeName: string;
    /// <summary>const, var, out, constref; '' ohne.</summary>
    Modifier: string;
    /// <summary>Wert als Delphi-Literal; '' = Platzhalter passend zum Typ.</summary>
    Value: string;
    /// <summary>Nicht übernehmbarer Wert (Objekt, Zeiger, großes Array): Kommentar statt Wert.</summary>
    Todo: Boolean;
    /// <summary>Nur Felder: von der Testunit aus zuweisbar (public/published); sonst nur als Kommentar.</summary>
    Accessible: Boolean;
    class function Create(const AName, ATypeName, AModifier, AValue: string): TTestDraftValue; static;
  end;

  {$SCOPEDENUMS ON}
  /// <summary>Was der Test erwartet: ein Ergebnis oder eine Exception.</summary>
  TTestDraftKind = (Works, Raises);
  {$SCOPEDENUMS OFF}

  /// <summary>Alles, woraus der Testcode entsteht.</summary>
  TTestDraft = record
    Fixture: string;
    TestName: string;
    /// <summary>Getestete Klasse; '' bei Routinen.</summary>
    ClassName: string;
    MethodName: string;
    /// <summary>class function/procedure: Aufruf über die Klasse statt über ein Objekt.</summary>
    ClassMethod: Boolean;
    /// <summary>Feld der Testklasse mit dem Objekt unter Test (FSubject); '' = lokales Objekt.</summary>
    Subject: string;
    /// <summary>Erzeugt das lokale Objekt (TKunde.Create); '' = nil mit Hinweis.</summary>
    CreateText: string;
    Parameters: TArray<TTestDraftValue>;
    Fields: TArray<TTestDraftValue>;
    /// <summary>Ergebnistyp bei Funktionen; '' bei Prozeduren.</summary>
    ResultType: string;
    /// <summary>Erwartetes Ergebnis als Literal; '' = Platzhalter.</summary>
    Expected: string;
    Kind: TTestDraftKind;
    /// <summary>Erwartete Exception bei Kind = Raises.</summary>
    ExceptionClass: string;
    /// <summary>Kommentarzeile über dem Rumpf (ohne //); '' ohne.</summary>
    Comment: string;
    /// <summary>Entwurf: Assert.Fail am Ende, bis die Werte stimmen.</summary>
    Draft: Boolean;
    /// <summary>Kopf unbekannt oder Methode von außen nicht aufrufbar: nur Assert.Fail, kein Aufruf.</summary>
    Bare: Boolean;
    /// <summary>Getestete Unit; kommt beim Eintragen ins uses der Testunit.</summary>
    UnitName: string;
    /// <summary>Fertige Attribute über der Deklaration ([TestCase('…', '…')]); leer: nur [Test].</summary>
    Attributes: TArray<string>;
    /// <summary>Werte als Parameter der Testmethode (#2173): die Parameter der Routine und bei Funktionen
    /// AExpected; der Rumpf ruft nur auf und prüft das Ergebnis.</summary>
    Parameterized: Boolean;
    /// <summary>Klasse.Methode bzw. Routine für Texte.</summary>
    function Target: string;
  end;

  TTestDrafts = class
  public const
    cActualName = 'Actual';
    cSubjectName = 'Subject';
    cFloatTolerance = '1E-9';
    cExpectedName = 'AExpected';
  public
    /// <summary>Methode oder Routine an der Zeile (0-basiert), im Rumpf oder an der Deklaration; liefert die
    /// Deklaration (bei Methoden die in der Klasse). False ohne, bei Konstruktoren, Destruktoren und Methoden
    /// von Records oder Helfern.</summary>
    class function RoutineAt(const AUnit: TUnitIndex; ALine: Integer; out ADeclaration: TIndexSymbol): Boolean;
      static;
    /// <summary>Kopf der Deklaration ADeclaration aus dem Quelltext (Token der Unit).</summary>
    class function HeaderOf(const AText: string; const ATokens: TArray<TPascalToken>;
      const ADeclaration: TIndexSymbol; out AHeader: TSignatureHeader): Boolean; static;
    /// <summary>Entwurf für die Methode bzw. Routine an der Zeile (0-basiert) der Unit AText; Fixture setzt der
    /// Aufrufer. False, wenn dort keine testbare steht.</summary>
    class function DraftAt(const AText: string; const ATokens: TArray<TPascalToken>; const AUnit: TUnitIndex;
      ALine: Integer; out ADraft: TTestDraft): Boolean; static;
    /// <summary>Entwurf zu einem Kopf: Parameter mit Platzhaltern, Ergebnistyp, Klassenmethode.</summary>
    class function FromHeader(const AFixture, AClassName: string; const AHeader: TSignatureHeader): TTestDraft;
      static;
    /// <summary>Platzhalter für einen Wert des Typs: 0, '', False, nil, Default(T).</summary>
    class function Placeholder(const ATypeName: string): string; static;
    /// <summary>Name der lokalen Variablen zum Parameter: AMenge wird Menge, wenn das frei und kein reserviertes
    /// Wort ist.</summary>
    class function LocalName(const AParameter: string; const ATaken: TArray<string>): string; static;
    /// <summary>Parameterliste der Testmethode mit Klammern ('' ohne Parameter); nur bei Parameterized.</summary>
    class function ParameterList(const ADraft: TTestDraft): string; static;
    /// <summary>Rumpf der Testmethode samt Kopf "procedure Fixture.TestName;", ohne Zeilenumbruch am Ende.
    /// </summary>
    class function MethodText(const ADraft: TTestDraft; const ALineBreak: string): string; static;
    /// <summary>Trägt den Test ADraft in die Testunit AText ein (Name nummeriert, wenn es ihn gibt) samt
    /// ADraft.UnitName im uses. AOnlyIfMissing: gibt es den Test schon, bleibt der Text unverändert. AName: der
    /// eingetragene Name.</summary>
    class function AddToTestUnit(const AText: string; const ADraft: TTestDraft; AOnlyIfMissing: Boolean;
      out ANewText, AName, AReason: string): Boolean; static;
    /// <summary>Feld der Testklasse AFixture vom Typ AClassName (das Objekt unter Test); '' ohne.</summary>
    class function SubjectField(const ATestUnit: TUnitIndex; const AFixture, AClassName: string): string; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Editing.UsesClause,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TTestDraftsText = (Arrange, Act, Assert_, ActAndAssert, DraftMarker, BuildValue, NotAccessible, ChooseType,
    CreateSubject, NoTestClass, NoClassEnd, TestMissing);

const
  cTexts: array[TTestDraftsText] of TAtlasText = (
    (De: '// Vorbereiten'; En: '// Arrange'),
    (De: '// Ausführen'; En: '// Act'),
    (De: '// Prüfen'; En: '// Assert'),
    (De: '// Ausführen und prüfen'; En: '// Act and assert'),
    (De: 'Entwurf für %s: erwartete Werte eintragen und diese Zeile löschen';
     En: 'Draft for %s: enter the expected values and delete this line'),
    (De: 'TODO: %s aufbauen (%s)'; En: 'TODO: build %s (%s)'),
    (De: '%s = %s (nicht zugänglich: über Konstruktor oder Property setzen)';
     En: '%s = %s (not accessible: set it via constructor or property)'),
    (De: 'TODO: Typ für %s wählen'; En: 'TODO: choose a type for %s'),
    (De: 'TODO: %s anlegen'; En: 'TODO: create %s'),
    (De: 'Die Testunit hat keine Testklasse'; En: 'The test unit has no test class'),
    (De: 'Testklasse oder Ende der Unit nicht gefunden'; En: 'Test class or end of the unit not found'),
    (De: 'Test für %s fehlt noch'; En: 'Test for %s still missing'));

{$SCOPEDENUMS OFF}

const
  cIntegerTypes: array[0..19] of string = ('Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt',
    'Byte', 'Word', 'LongInt', 'LongWord', 'ShortInt', 'SmallInt', 'FixedInt', 'FixedUInt', 'Int8', 'Int16',
    'Int32', 'UInt8', 'UInt16', 'UInt32');
  cFloatTypes: array[0..8] of string = ('Double', 'Single', 'Extended', 'Real', 'Currency', 'TDateTime', 'TDate',
    'TTime', 'Comp');
  cStringTypes: array[0..7] of string = ('string', 'AnsiString', 'UnicodeString', 'WideString', 'RawByteString',
    'UTF8String', 'ShortString', 'TFileName');
  cCharTypes: array[0..2] of string = ('Char', 'WideChar', 'AnsiChar');
  cBooleanTypes: array[0..3] of string = ('Boolean', 'ByteBool', 'WordBool', 'LongBool');
  cPointerTypes: array[0..6] of string = ('Pointer', 'TObject', 'PChar', 'PAnsiChar', 'PWideChar', 'IInterface',
    'IUnknown');

{$SCOPEDENUMS ON}

type
  /// <summary>Grobe Art eines Typs für Platzhalter und Prüfungen.</summary>
  TValueKind = (Other, Integer_, Float, Text, Char_, Boolean_, Reference);

{$SCOPEDENUMS OFF}

/// <summary>Zeiger, Objekt, Interface oder dynamisches Array: Platzhalter nil.</summary>
function IsReferenceType(const AName: string): Boolean;
begin
  Result := MatchText(AName, cPointerTypes) or StartsText('array of', AName) or StartsText('TArray<', AName);
  if not Result and (Length(AName) > 1) then
  begin
    Result := (AName[1] = 'I') and CharInSet(AName[2], ['A'..'Z']);
  end;
end;

function ValueKindOf(const ATypeName: string): TValueKind;
var
  mName: string;
begin
  mName := Trim(ATypeName);
  if MatchText(mName, cIntegerTypes) then
  begin
    Result := TValueKind.Integer_;
  end
  else if MatchText(mName, cFloatTypes) then
  begin
    Result := TValueKind.Float;
  end
  else if MatchText(mName, cStringTypes) or StartsText('string[', mName) then
  begin
    Result := TValueKind.Text;
  end
  else if MatchText(mName, cCharTypes) then
  begin
    Result := TValueKind.Char_;
  end
  else if MatchText(mName, cBooleanTypes) then
  begin
    Result := TValueKind.Boolean_;
  end
  else if IsReferenceType(mName) then
  begin
    Result := TValueKind.Reference;
  end
  else
  begin
    Result := TValueKind.Other;
  end;
end;

{ TTestDraftValue }

class function TTestDraftValue.Create(const AName, ATypeName, AModifier, AValue: string): TTestDraftValue;
begin
  Result := Default(TTestDraftValue);
  Result.Name := AName;
  Result.TypeName := ATypeName;
  Result.Modifier := AModifier;
  Result.Value := AValue;
  Result.Accessible := True;
end;

{ TTestDraft }

function TTestDraft.Target: string;
begin
  Result := MethodName;
  if ClassName <> '' then
  begin
    Result := ClassName + '.' + MethodName;
  end;
end;

{ TTestDrafts }

class function TTestDrafts.Placeholder(const ATypeName: string): string;
begin
  case ValueKindOf(ATypeName) of
    TValueKind.Integer_, TValueKind.Float:
      Result := '0';
    TValueKind.Text:
      Result := '''''';
    TValueKind.Char_:
      Result := '#0';
    TValueKind.Boolean_:
      Result := 'False';
    TValueKind.Reference:
      Result := 'nil';
  else
    if ATypeName = '' then
    begin
      Result := '0';
    end
    else
    begin
      Result := 'Default(' + Trim(ATypeName) + ')';
    end;
  end;
end;

class function TTestDrafts.LocalName(const AParameter: string; const ATaken: TArray<string>): string;
var
  mNumber: Integer;
begin
  Result := AParameter;
  if (Length(AParameter) > 1) and (AParameter[1] = 'A') and CharInSet(AParameter[2], ['A'..'Z']) then
  begin
    Result := Copy(AParameter, 2, MaxInt);
  end;
  if TPascalLexer.IsReservedWord(Result) or MatchText(Result, ATaken) then
  begin
    Result := AParameter;
  end;
  mNumber := 1;
  while TPascalLexer.IsReservedWord(Result) or MatchText(Result, ATaken) do
  begin
    Inc(mNumber);
    Result := AParameter + IntToStr(mNumber);
  end;
end;

function IsRoutineKind(const ASymbol: TIndexSymbol): Boolean;
begin
  Result := ASymbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine];
end;

function IsClassNamed(const AUnit: TUnitIndex; const AName: string): Boolean;
var
  mSymbol: TIndexSymbol;
  mName: string;
begin
  mName := AName;
  if Pos('<', mName) > 0 then
  begin
    mName := Copy(mName, 1, Pos('<', mName) - 1);
  end;
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.ClassType) and SameText(mSymbol.Name, mName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Gleiche Parametertypen (Rumpf mit Parametern gegen Deklaration).</summary>
function SameParamTypes(const AFirst, ASecond: TArray<string>): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(AFirst) = Length(ASecond);
  if not Result then
  begin
    Exit;
  end;
  for mIndex := 0 to High(AFirst) do
  begin
    if not SameText(AFirst[mIndex], ASecond[mIndex]) then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Deklaration zum Rumpf ABody: erste Methode bzw. Routine gleichen Namens davor, bei Überladungen die mit
/// denselben Parametertypen.</summary>
function DeclarationOf(const AUnit: TUnitIndex; const ABody: TIndexSymbol): TIndexSymbol;
var
  mSymbol: TIndexSymbol;
  mFound: Boolean;
begin
  Result := ABody;
  mFound := False;
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Range.StartPos.Line >= ABody.Range.StartPos.Line) or not IsRoutineKind(mSymbol) or
      (mSymbol.Kind <> ABody.Kind) or not SameText(mSymbol.Name, ABody.Name) or
      not SameText(mSymbol.Container, ABody.Container) then
    begin
      Continue;
    end;
    if (Length(ABody.ParamTypes) = 0) or SameParamTypes(mSymbol.ParamTypes, ABody.ParamTypes) then
    begin
      Exit(mSymbol);
    end;
    if not mFound then
    begin
      Result := mSymbol;
      mFound := True;
    end;
  end;
end;

class function TTestDrafts.RoutineAt(const AUnit: TUnitIndex; ALine: Integer;
  out ADeclaration: TIndexSymbol): Boolean;
var
  mSymbol, mBest: TIndexSymbol;
begin
  ADeclaration := Default(TIndexSymbol);
  Result := False;
  mBest := Default(TIndexSymbol);
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine, TIndexSymbolKind.Constructor_]) and
      (mSymbol.Range.StartPos.Line <= ALine) and (mSymbol.Range.EndPos.Line >= ALine) and
      (not Result or (mSymbol.Range.StartPos.Line >= mBest.Range.StartPos.Line)) then
    begin
      mBest := mSymbol;
      Result := True;
    end;
  end;
  if not Result or not IsRoutineKind(mBest) or SameText(mBest.Name, 'Destroy') then
  begin
    Exit(False);
  end;
  ADeclaration := DeclarationOf(AUnit, mBest);
  // Methoden nur von Klassen (nicht Records, Helfer, verschachtelte Routinen).
  if ADeclaration.Kind = TIndexSymbolKind.Method then
  begin
    Result := IsClassNamed(AUnit, ADeclaration.Container);
  end
  else
  begin
    Result := ADeclaration.Container = '';
  end;
end;

class function TTestDrafts.HeaderOf(const AText: string; const ATokens: TArray<TPascalToken>;
  const ADeclaration: TIndexSymbol; out AHeader: TSignatureHeader): Boolean;
var
  mNameToken: Integer;
begin
  mNameToken := TChangeSignature.NameTokenAt(ATokens, ADeclaration.SelectionRange.StartPos);
  Result := TChangeSignature.ReadHeader(AText, ATokens, mNameToken, AHeader);
end;

class function TTestDrafts.DraftAt(const AText: string; const ATokens: TArray<TPascalToken>;
  const AUnit: TUnitIndex; ALine: Integer; out ADraft: TTestDraft): Boolean;
var
  mDeclaration: TIndexSymbol;
  mHeader: TSignatureHeader;
  mClassName: string;
begin
  ADraft := Default(TTestDraft);
  Result := RoutineAt(AUnit, ALine, mDeclaration) and HeaderOf(AText, ATokens, mDeclaration, mHeader);
  if not Result then
  begin
    Exit;
  end;
  mClassName := mDeclaration.Container;
  if Pos('<', mClassName) > 0 then
  begin
    mClassName := Copy(mClassName, 1, Pos('<', mClassName) - 1);
  end;
  ADraft := FromHeader('', mClassName, mHeader);
  // Von der Testunit aus nicht aufrufbar (privat, geschützt, nur im implementation-Teil): nur Assert.Fail.
  ADraft.Bare := not mDeclaration.InInterface or
    not (mDeclaration.Visibility in [TIndexVisibility.Public, TIndexVisibility.Published]);
end;

class function TTestDrafts.FromHeader(const AFixture, AClassName: string;
  const AHeader: TSignatureHeader): TTestDraft;
var
  mParameter: TSignatureParameter;
  mDot: Integer;
begin
  Result := Default(TTestDraft);
  Result.Fixture := AFixture;
  Result.ClassName := AClassName;
  Result.MethodName := AHeader.QualifiedName;
  mDot := LastDelimiter('.', Result.MethodName);
  if mDot > 0 then
  begin
    Result.MethodName := Copy(Result.MethodName, mDot + 1, MaxInt);
  end;
  if Pos('<', Result.MethodName) > 0 then
  begin
    Result.MethodName := Copy(Result.MethodName, 1, Pos('<', Result.MethodName) - 1);
  end;
  Result.TestName := 'Test' + Result.MethodName;
  Result.ClassMethod := AHeader.IsClass;
  Result.ResultType := AHeader.ResultType;
  Result.Draft := True;
  for mParameter in AHeader.Parameters do
  begin
    Result.Parameters := Result.Parameters + [TTestDraftValue.Create(mParameter.Name, mParameter.TypeName,
      LowerCase(mParameter.Modifier), '')];
  end;
end;

type
  /// <summary>Schreibt die Testmethode Zeile für Zeile.</summary>
  TDraftWriter = record
    Builder: TStringBuilder;
    LineBreak: string;
    Draft: TTestDraft;
    Locals: TArray<string>;
    Subject: string;
    LocalSubject: Boolean;
    procedure Line(const AText: string);
    function ValueText(const AValue: TTestDraftValue): string;
    function CallText: string;
    function CheckText(const AExpected, AActual, ATypeName: string): string;
    procedure WriteVariables;
    procedure WriteArrange(const AIndent: string);
    procedure WriteWorks(const AIndent: string);
    /// <summary>Aufruf und Prüfung gegen AExpected einer Testmethode mit Parametern.</summary>
    procedure WriteCall(const AIndent: string);
    procedure WriteRaises(const AIndent: string);
    procedure Prepare(const ADraft: TTestDraft);
    procedure WriteBare;
    /// <summary>Lokales Objekt anlegen und try; Einrückung des Rumpfs danach.</summary>
    function WriteSubjectStart: string;
    procedure WriteBody;
  end;

procedure TDraftWriter.Line(const AText: string);
begin
  Builder.Append(LineBreak).Append(AText);
end;

function TDraftWriter.ValueText(const AValue: TTestDraftValue): string;
begin
  Result := AValue.Value;
  if (Result = '') or AValue.Todo then
  begin
    Result := TTestDrafts.Placeholder(AValue.TypeName);
  end;
end;

function TDraftWriter.CallText: string;
var
  mIndex: Integer;
  mArguments: string;
begin
  mArguments := '';
  for mIndex := 0 to High(Draft.Parameters) do
  begin
    if mIndex > 0 then
    begin
      mArguments := mArguments + ', ';
    end;
    mArguments := mArguments + Locals[mIndex];
  end;
  Result := Draft.MethodName;
  if Draft.ClassMethod then
  begin
    Result := Draft.ClassName + '.' + Result;
  end
  else if Subject <> '' then
  begin
    Result := Subject + '.' + Result;
  end;
  if mArguments <> '' then
  begin
    Result := Result + '(' + mArguments + ')';
  end;
end;

function TDraftWriter.CheckText(const AExpected, AActual, ATypeName: string): string;
var
  mExpected: string;
begin
  mExpected := AExpected;
  case ValueKindOf(ATypeName) of
    TValueKind.Float:
      begin
        if mExpected = '' then
        begin
          mExpected := '0.0';
        end;
        Result := 'Assert.AreEqual(' + mExpected + ', ' + AActual + ', ' + TTestDrafts.cFloatTolerance + ');';
      end;
    TValueKind.Boolean_:
      if SameText(mExpected, 'False') then
      begin
        Result := 'Assert.IsFalse(' + AActual + ');';
      end
      else
      begin
        Result := 'Assert.IsTrue(' + AActual + ');';
      end;
    TValueKind.Reference:
      if mExpected = '' then
      begin
        Result := 'Assert.IsNotNull(' + AActual + ');';
      end
      else
      begin
        Result := 'Assert.AreEqual(' + mExpected + ', ' + AActual + ');';
      end;
    TValueKind.Integer_, TValueKind.Text, TValueKind.Char_:
      begin
        if mExpected = '' then
        begin
          mExpected := TTestDrafts.Placeholder(ATypeName);
        end;
        if SameText(mExpected, '#0') then
        begin
          mExpected := '''''';
        end;
        Result := 'Assert.AreEqual(' + mExpected + ', ' + AActual + ');';
      end;
  else
    if mExpected = '' then
    begin
      mExpected := TTestDrafts.Placeholder(ATypeName);
    end;
    Result := 'Assert.AreEqual<' + Trim(ATypeName) + '>(' + mExpected + ', ' + AActual + ');';
  end;
end;

procedure TDraftWriter.WriteVariables;
var
  mIndex: Integer;
  mType: string;
  mLines: TArray<string>;
begin
  mLines := nil;
  if LocalSubject then
  begin
    mLines := mLines + ['  ' + Subject + ': ' + Draft.ClassName + ';'];
  end;
  for mIndex := 0 to High(Draft.Parameters) do
  begin
    if Draft.Parameterized then
    begin
      Break;
    end;
    mType := Draft.Parameters[mIndex].TypeName;
    if mType = '' then
    begin
      mType := 'Integer';
    end
    else if StartsText('array of', mType) then
    begin
      mType := 'TArray<' + Trim(Copy(mType, Length('array of') + 1, MaxInt)) + '>';
    end;
    mLines := mLines + ['  ' + Locals[mIndex] + ': ' + mType + ';'];
  end;
  if (Draft.ResultType <> '') and (Draft.Kind = TTestDraftKind.Works) then
  begin
    mLines := mLines + ['  ' + TTestDrafts.cActualName + ': ' + Draft.ResultType + ';'];
  end;
  if Length(mLines) = 0 then
  begin
    Exit;
  end;
  Line('var');
  for mType in mLines do
  begin
    Line(mType);
  end;
end;

procedure TDraftWriter.WriteArrange(const AIndent: string);
var
  mIndex: Integer;
  mValue: TTestDraftValue;
  mText: string;
begin
  if Draft.Parameterized or ((Length(Draft.Parameters) = 0) and (Length(Draft.Fields) = 0)) then
  begin
    Exit;
  end;
  Line(AIndent + cTexts[TTestDraftsText.Arrange].Text);
  for mIndex := 0 to High(Draft.Parameters) do
  begin
    mValue := Draft.Parameters[mIndex];
    mText := AIndent + Locals[mIndex] + ' := ' + ValueText(mValue) + ';';
    if mValue.TypeName = '' then
    begin
      mText := mText + ' // ' + cTexts[TTestDraftsText.ChooseType].Fmt([mValue.Name]);
    end
    else if mValue.Todo then
    begin
      mText := mText + ' // ' + cTexts[TTestDraftsText.BuildValue].Fmt([Locals[mIndex], mValue.TypeName]);
    end;
    Line(mText);
  end;
  for mValue in Draft.Fields do
  begin
    if mValue.Accessible and not mValue.Todo and (Subject <> '') and not Draft.ClassMethod then
    begin
      Line(AIndent + Subject + '.' + mValue.Name + ' := ' + ValueText(mValue) + ';');
    end
    else if mValue.Todo then
    begin
      Line(AIndent + '// ' + cTexts[TTestDraftsText.BuildValue].Fmt([mValue.Name, mValue.TypeName]));
    end
    else
    begin
      Line(AIndent + '// ' + cTexts[TTestDraftsText.NotAccessible].Fmt([mValue.Name, ValueText(mValue)]));
    end;
  end;
end;

/// <summary>Prüfung des Ergebnisses gegen den Parameter AExpected.</summary>
function ExpectedCheck(const ATypeName: string): string;
begin
  case ValueKindOf(ATypeName) of
    TValueKind.Float:
      Result := 'Assert.AreEqual(' + TTestDrafts.cExpectedName + ', ' + TTestDrafts.cActualName + ', ' +
        TTestDrafts.cFloatTolerance + ');';
    TValueKind.Integer_, TValueKind.Text, TValueKind.Char_:
      Result := 'Assert.AreEqual(' + TTestDrafts.cExpectedName + ', ' + TTestDrafts.cActualName + ');';
  else
    Result := 'Assert.AreEqual<' + Trim(ATypeName) + '>(' + TTestDrafts.cExpectedName + ', ' +
      TTestDrafts.cActualName + ');';
  end;
end;

procedure TDraftWriter.WriteWorks(const AIndent: string);
var
  mIndex: Integer;
  mChecks: TArray<string>;
  mCheck: string;
begin
  if Draft.Parameterized then
  begin
    WriteCall(AIndent);
    Exit;
  end;
  Line(AIndent + cTexts[TTestDraftsText.Act].Text);
  if Draft.ResultType <> '' then
  begin
    Line(AIndent + TTestDrafts.cActualName + ' := ' + CallText + ';');
  end
  else
  begin
    Line(AIndent + CallText + ';');
  end;
  mChecks := nil;
  if Draft.ResultType <> '' then
  begin
    mChecks := mChecks + [CheckText(Draft.Expected, TTestDrafts.cActualName, Draft.ResultType)];
  end;
  for mIndex := 0 to High(Draft.Parameters) do
  begin
    if MatchText(Draft.Parameters[mIndex].Modifier, ['var', 'out']) and (Draft.Parameters[mIndex].TypeName <> '')
    then
    begin
      mChecks := mChecks + [CheckText('', Locals[mIndex], Draft.Parameters[mIndex].TypeName)];
    end;
  end;
  if Draft.Draft then
  begin
    mChecks := mChecks + ['Assert.Fail(' + QuotedStr(cTexts[TTestDraftsText.DraftMarker].Fmt([Draft.Target])) +
      ');'];
  end;
  if Length(mChecks) = 0 then
  begin
    Exit;
  end;
  Line(AIndent + cTexts[TTestDraftsText.Assert_].Text);
  for mCheck in mChecks do
  begin
    Line(AIndent + mCheck);
  end;
end;

procedure TDraftWriter.WriteCall(const AIndent: string);
begin
  if Draft.ResultType = '' then
  begin
    Line(AIndent + CallText + ';');
    Exit;
  end;
  Line(AIndent + TTestDrafts.cActualName + ' := ' + CallText + ';');
  Line(AIndent + ExpectedCheck(Draft.ResultType));
end;

procedure TDraftWriter.WriteRaises(const AIndent: string);
var
  mClass: string;
begin
  Line(AIndent + cTexts[TTestDraftsText.ActAndAssert].Text);
  Line(AIndent + 'Assert.WillRaise(');
  Line(AIndent + '  procedure');
  Line(AIndent + '  begin');
  Line(AIndent + '    ' + CallText + ';');
  mClass := Draft.ExceptionClass;
  if mClass = '' then
  begin
    mClass := 'Exception';
  end;
  Line(AIndent + '  end, ' + mClass + ');');
  if Draft.Draft then
  begin
    Line(AIndent + 'Assert.Fail(' + QuotedStr(cTexts[TTestDraftsText.DraftMarker].Fmt([Draft.Target])) + ');');
  end;
end;

procedure TDraftWriter.Prepare(const ADraft: TTestDraft);
var
  mValue: TTestDraftValue;
begin
  Draft := ADraft;
  Subject := ADraft.Subject;
  LocalSubject := (ADraft.ClassName <> '') and not ADraft.ClassMethod and (ADraft.Subject = '');
  if LocalSubject then
  begin
    Subject := TTestDrafts.cSubjectName;
  end;
  Locals := [TTestDrafts.cActualName, TTestDrafts.cSubjectName, 'Assert'];
  for mValue in ADraft.Parameters do
  begin
    Locals := Locals + [TTestDrafts.LocalName(mValue.Name, Locals)];
  end;
  Locals := Copy(Locals, 3, MaxInt);
  if ADraft.Parameterized then
  begin
    Locals := nil;
    for mValue in ADraft.Parameters do
    begin
      Locals := Locals + [mValue.Name];
    end;
  end;
end;

procedure TDraftWriter.WriteBare;
begin
  Line('begin');
  Line('  Assert.Fail(' + QuotedStr(cTexts[TTestDraftsText.TestMissing].Fmt([Draft.Target])) + ');');
  Line('end;');
end;

function TDraftWriter.WriteSubjectStart: string;
begin
  Result := '  ';
  if not LocalSubject then
  begin
    Exit;
  end;
  if Draft.CreateText = '' then
  begin
    Line('  ' + Subject + ' := nil; // ' + cTexts[TTestDraftsText.CreateSubject].Fmt([Draft.ClassName]));
  end
  else
  begin
    Line('  ' + Subject + ' := ' + Draft.CreateText + ';');
  end;
  Line('  try');
  Result := '    ';
end;

procedure TDraftWriter.WriteBody;
var
  mIndent: string;
begin
  WriteVariables;
  Line('begin');
  if Draft.Comment <> '' then
  begin
    Line('  // ' + Draft.Comment);
  end;
  mIndent := WriteSubjectStart;
  WriteArrange(mIndent);
  if Draft.Kind = TTestDraftKind.Raises then
  begin
    WriteRaises(mIndent);
  end
  else
  begin
    WriteWorks(mIndent);
  end;
  if LocalSubject then
  begin
    Line('  finally');
    Line('    ' + Subject + '.Free;');
    Line('  end;');
  end;
  Line('end;');
end;

class function TTestDrafts.MethodText(const ADraft: TTestDraft; const ALineBreak: string): string;
var
  mWriter: TDraftWriter;
begin
  mWriter := Default(TDraftWriter);
  mWriter.Builder := TStringBuilder.Create;
  try
    mWriter.LineBreak := ALineBreak;
    mWriter.Prepare(ADraft);
    mWriter.Builder.Append('procedure ' + ADraft.Fixture + '.' + ADraft.TestName + ParameterList(ADraft) + ';');
    if ADraft.Bare then
    begin
      mWriter.WriteBare;
    end
    else
    begin
      mWriter.WriteBody;
    end;
    Result := mWriter.Builder.ToString;
  finally
    mWriter.Builder.Free;
  end;
end;

class function TTestDrafts.ParameterList(const ADraft: TTestDraft): string;
var
  mParts: TArray<string>;
  mValue: TTestDraftValue;
begin
  Result := '';
  if not ADraft.Parameterized then
  begin
    Exit;
  end;
  mParts := nil;
  for mValue in ADraft.Parameters do
  begin
    mParts := mParts + ['const ' + mValue.Name + ': ' + mValue.TypeName];
  end;
  if ADraft.ResultType <> '' then
  begin
    mParts := mParts + ['const ' + cExpectedName + ': ' + ADraft.ResultType];
  end;
  if Length(mParts) > 0 then
  begin
    Result := '(' + string.Join('; ', mParts) + ')';
  end;
end;

{ Eintragen in die Testunit }

/// <summary>Index der Unit AText.</summary>
function UnitIndexOf(const AText: string): TUnitIndex;
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    Result := TIndexExtractor.Extract(mTree, '');
  finally
    mTree.Free;
  end;
end;

/// <summary>Testklasse: die Klasse AFixture, sonst die erste Klasse der Unit; False ohne Klasse.</summary>
function FixtureSymbol(const AIndex: TUnitIndex; const AFixture: string; out ASymbol: TIndexSymbol): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  ASymbol := Default(TIndexSymbol);
  Result := False;
  for mSymbol in AIndex.Symbols do
  begin
    if (mSymbol.Kind <> TIndexSymbolKind.ClassType) or (mSymbol.Container <> '') then
    begin
      Continue;
    end;
    if SameText(mSymbol.Name, AFixture) then
    begin
      ASymbol := mSymbol;
      Exit(True);
    end;
    if not Result then
    begin
      ASymbol := mSymbol;
      Result := True;
    end;
  end;
end;

/// <summary>Namen der Methoden der Klasse AFixture.</summary>
function FixtureMethods(const AIndex: TUnitIndex; const AFixture: string): TArray<string>;
var
  mSymbol: TIndexSymbol;
begin
  Result := nil;
  for mSymbol in AIndex.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Method) and SameText(mSymbol.Container, AFixture) then
    begin
      Result := Result + [mSymbol.Name];
    end;
  end;
end;

/// <summary>ATestName, bei Gleichnamigen in ANames nummeriert (ATestName2, ATestName3 …).</summary>
function FreeTestName(const ATestName: string; const ANames: TArray<string>): string;
var
  mNumber: Integer;
begin
  Result := ATestName;
  mNumber := 1;
  while MatchText(Result, ANames) do
  begin
    Inc(mNumber);
    Result := ATestName + IntToStr(mNumber);
  end;
end;

/// <summary>Zeile von "end" der Klassendeklaration ASymbol; -1 ohne.</summary>
function ClassEndLine(const ALines: TArray<string>; const ASymbol: TIndexSymbol): Integer;
begin
  Result := ASymbol.Range.EndPos.Line;
  if Result > High(ALines) then
  begin
    Result := High(ALines);
  end;
  while (Result > ASymbol.Range.StartPos.Line) and not StartsText('end', TrimLeft(ALines[Result])) do
  begin
    Dec(Result);
  end;
  if Result <= ASymbol.Range.StartPos.Line then
  begin
    Result := -1;
  end;
end;

/// <summary>Zeile, vor der neue Rümpfe stehen: initialization, finalization bzw. "end."; -1 ohne.</summary>
function BodyLine(const ALines: TArray<string>): Integer;
var
  mIndex: Integer;
  mLine: string;
begin
  Result := -1;
  for mIndex := High(ALines) downto 0 do
  begin
    mLine := LowerCase(Trim(ALines[mIndex]));
    if (Result < 0) and mLine.StartsWith('end.') then
    begin
      Result := mIndex;
    end
    else if (Result >= 0) and ((mLine = 'initialization') or (mLine = 'finalization')) then
    begin
      Result := mIndex;
    end;
  end;
end;

/// <summary>Edit, der AUnitName ins uses von AText einträgt; False, wenn sie dort schon steht oder kein Platz ist.
/// Vor dem Einfügen bestimmt; der Edit liegt vor allen anderen Stellen.</summary>
function UsesEditFor(const AText: string; const AFixture: TIndexSymbol; const AUnitName, ALineBreak: string;
  out AEdit: TTextEdit): Boolean;
var
  mTokens: TArray<TPascalToken>;
begin
  mTokens := TPascalLexer.Tokenize(AText);
  Result := (AUnitName <> '') and not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(mTokens), AUnitName, nil) and
    TUsesClauses.AddUnit(mTokens, TLineTable.Build(AText).OffsetAt(AFixture.Range.StartPos), AUnitName, ALineBreak,
    AEdit);
end;

/// <summary>AText mit AEdit angewandt.</summary>
function Applied(const AText: string; const AEdit: TTextEdit): string;
var
  mTable: TLineTable;
  mStart, mStop: Integer;
begin
  mTable := TLineTable.Build(AText);
  mStart := mTable.OffsetAt(AEdit.Range.StartPos);
  mStop := mTable.OffsetAt(AEdit.Range.EndPos);
  Result := Copy(AText, 1, mStart) + AEdit.NewText + Copy(AText, mStop + 1, MaxInt);
end;

/// <summary>Deklaration des Tests ADraft vor der Zeile AEndLine ("end" der Klasse), eine Ebene tiefer, mit
/// [Test] bzw. seinen Attributen.</summary>
function DeclarationText(const ADraft: TTestDraft; const ALineBreak, AEndLine: string): string;
var
  mIndent, mAttribute: string;
  mAttributes: TArray<string>;
begin
  mIndent := Copy(AEndLine, 1, Length(AEndLine) - Length(TrimLeft(AEndLine))) + '  ';
  mAttributes := ADraft.Attributes;
  if Length(mAttributes) = 0 then
  begin
    mAttributes := ['[Test]'];
  end;
  Result := '';
  for mAttribute in mAttributes do
  begin
    Result := Result + mIndent + mAttribute + ALineBreak;
  end;
  Result := Result + mIndent + 'procedure ' + ADraft.TestName + TTestDrafts.ParameterList(ADraft) + ';' +
    ALineBreak + AEndLine;
end;

class function TTestDrafts.AddToTestUnit(const AText: string; const ADraft: TTestDraft; AOnlyIfMissing: Boolean;
  out ANewText, AName, AReason: string): Boolean;
var
  mIndex: TUnitIndex;
  mFixture: TIndexSymbol;
  mNames, mLines: TArray<string>;
  mLineBreak: string;
  mEndLine, mBody: Integer;
  mUsesEdit: TTextEdit;
  mNeedsUses: Boolean;
  mDraft: TTestDraft;
begin
  ANewText := '';
  AName := '';
  AReason := '';
  mIndex := UnitIndexOf(AText);
  if not FixtureSymbol(mIndex, ADraft.Fixture, mFixture) then
  begin
    AReason := cTexts[TTestDraftsText.NoTestClass].Text;
    Exit(False);
  end;
  mNames := FixtureMethods(mIndex, mFixture.Name);
  if MatchText(ADraft.TestName, mNames) and AOnlyIfMissing then
  begin
    ANewText := AText;
    AName := ADraft.TestName;
    Exit(True);
  end;
  mDraft := ADraft;
  mDraft.Fixture := mFixture.Name;
  mDraft.TestName := FreeTestName(ADraft.TestName, mNames);
  if (mDraft.Subject = '') and (mDraft.ClassName <> '') and not mDraft.ClassMethod then
  begin
    mDraft.Subject := SubjectField(mIndex, mFixture.Name, mDraft.ClassName);
  end;
  mLineBreak := TTextLines.LineBreakOf(AText);
  mLines := AText.Split([mLineBreak]);
  mEndLine := ClassEndLine(mLines, mFixture);
  mBody := BodyLine(mLines);
  if (mEndLine < 0) or (mBody < 0) then
  begin
    AReason := cTexts[TTestDraftsText.NoClassEnd].Text;
    Exit(False);
  end;
  mNeedsUses := UsesEditFor(AText, mFixture, ADraft.UnitName, mLineBreak, mUsesEdit);
  mLines[mBody] := MethodText(mDraft, mLineBreak) + mLineBreak + mLineBreak + mLines[mBody];
  mLines[mEndLine] := DeclarationText(mDraft, mLineBreak, mLines[mEndLine]);
  ANewText := string.Join(mLineBreak, mLines);
  if mNeedsUses then
  begin
    ANewText := Applied(ANewText, mUsesEdit);
  end;
  AName := mDraft.TestName;
  Result := True;
end;

class function TTestDrafts.SubjectField(const ATestUnit: TUnitIndex; const AFixture, AClassName: string): string;
var
  mSymbol: TIndexSymbol;
begin
  Result := '';
  for mSymbol in ATestUnit.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Field) and SameText(mSymbol.Container, AFixture) and
      SameText(mSymbol.TypeName, AClassName) then
    begin
      Exit(mSymbol.Name);
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.TestDrafts', cTexts);

end.
