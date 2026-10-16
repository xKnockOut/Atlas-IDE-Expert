unit Atlas.Common.Editing.TestUnits;

// DUnitX-Testgerüst (#274) und Zuordnung zwischen Unit und Testunit (#189).
// Die Namen folgen dem Muster "testUnits.pattern" ({unit} = Name der
// getesteten Unit, Vorgabe "{unit}.Tests"). Das Gerüst enthält [TestFixture],
// [Setup] und [TearDown] mit dem Objekt unter Test und einen [Test] je
// öffentlicher Methode der Klasse (überladene durchnummeriert); ohne Klasse
// einen Test je Routine im interface. Jeder Test schlägt fehl, bis er
// geschrieben ist, damit kein leerer Test grün durchläuft.
// Reine Textfunktionen; Dateien, Index und Testprojekt liefert der Aufrufer.

interface

uses
  System.SysUtils,
  Atlas.Common.Index.Contract;

type
  /// <summary>Ein Test des Gerüsts: Name der Testmethode und was er prüft.</summary>
  TTestUnitMethod = record
    /// <summary>Name der Testmethode, z. B. TestBerechne oder TestBerechne2.</summary>
    Name: string;
    /// <summary>Geprüfte Methode bzw. Routine, z. B. TKunde.Berechne.</summary>
    Target: string;
  end;

  /// <summary>Text einer Datei; '' wenn sie fehlt.</summary>
  TTestUnitReadText = reference to function(const AFileName: string): string;

  TTestUnits = class
  public const
    DefaultPattern = '{unit}.Tests';
    Placeholder = '{unit}';
  public
    /// <summary>Name der Testunit zu AUnitName nach APattern; leeres Muster gilt als Vorgabe.</summary>
    class function TestUnitName(const AUnitName, APattern: string): string; static;
    /// <summary>Getestete Unit zu einer Testunit; False, wenn der Name nicht zum Muster passt.</summary>
    class function TestedUnitName(const ATestUnitName, APattern: string; out AUnitName: string): Boolean; static;
    /// <summary>Name der Fixture: TKunde wird TKundeTests; ohne Klasse der letzte Namensteil der
    /// Unit (Kunden.Logik wird TLogikTests).</summary>
    class function FixtureName(const AClassName, AUnitName: string): string; static;
    /// <summary>Klasse an der Zeile (0-basiert): ihre Deklaration oder eine ihrer Methoden im
    /// implementation-Teil; '' sonst.</summary>
    class function ClassAt(const AUnit: TUnitIndex; ALine: Integer): string; static;
    /// <summary>Erste Klasse im interface; '' ohne.</summary>
    class function FirstClass(const AUnit: TUnitIndex): string; static;
    /// <summary>Tests zu den public- und published-Methoden von AClassName (ohne Konstruktoren und
    /// Destroy); bei leerem AClassName zu den Routinen im interface.</summary>
    class function TestMethods(const AUnit: TUnitIndex; const AClassName: string): TArray<TTestUnitMethod>; static;
    /// <summary>Ausdruck, der ein Objekt der Klasse erzeugt (TKunde.Create, TForm1.Create(nil));
    /// '' wenn der Konstruktor Argumente braucht oder die Klasse generisch ist.</summary>
    class function CreateExpression(const AUnit: TUnitIndex; const AClassName: string): string; static;
    /// <summary>Text der Testunit. AClassName leer: Tests für die Routinen der Unit.</summary>
    class function UnitText(const ATestUnitName: string; const AUnit: TUnitIndex; const AClassName: string;
      const ALineBreak: string): string; static;
    /// <summary>Bindet die Programmdatei DUnitX oder DUnit ein?</summary>
    class function IsTestProgram(const AText: string): Boolean; static;
    /// <summary>Erstes Testprogramm (.dpr) unter ACandidates; '' ohne.</summary>
    class function FindTestProgram(const ACandidates: TArray<string>; const AReadText: TTestUnitReadText): string; static;
    /// <summary>Pfad von AFileName relativ zum Ordner ABaseDir, mit \ wie in .dpr und .dproj;
    /// AFileName unverändert, wenn es auf einem anderen Laufwerk liegt.</summary>
    class function RelativePath(const ABaseDir, AFileName: string): string; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.UsesClause;

function PatternOrDefault(const APattern: string): string;
begin
  Result := APattern;
  if Pos(TTestUnits.Placeholder, Result) = 0 then
    Result := TTestUnits.DefaultPattern;
end;

class function TTestUnits.TestUnitName(const AUnitName, APattern: string): string;
begin
  Result := StringReplace(PatternOrDefault(APattern), Placeholder, AUnitName, [rfIgnoreCase]);
end;

class function TTestUnits.TestedUnitName(const ATestUnitName, APattern: string; out AUnitName: string): Boolean;
var
  Pattern, Prefix, Suffix: string;
  At: Integer;
begin
  AUnitName := '';
  Pattern := PatternOrDefault(APattern);
  At := Pos(Placeholder, Pattern);
  Prefix := Copy(Pattern, 1, At - 1);
  Suffix := Copy(Pattern, At + Length(Placeholder), MaxInt);
  Result := (Length(ATestUnitName) > Length(Prefix) + Length(Suffix)) and StartsText(Prefix, ATestUnitName) and
    EndsText(Suffix, ATestUnitName);
  if Result then
    AUnitName := Copy(ATestUnitName, Length(Prefix) + 1, Length(ATestUnitName) - Length(Prefix) - Length(Suffix));
end;

class function TTestUnits.FixtureName(const AClassName, AUnitName: string): string;
var
  Name: string;
  Dot: Integer;
begin
  if AClassName <> '' then
  begin
    Name := AClassName;
    if (Length(Name) > 1) and CharInSet(Name[1], ['T', 't']) and CharInSet(Name[2], ['A'..'Z']) then
      Name := Copy(Name, 2, MaxInt);
  end
  else
  begin
    Name := AUnitName;
    Dot := Name.LastIndexOf('.');
    if Dot >= 0 then
      Name := Name.Substring(Dot + 1);
  end;
  Result := 'T' + Name + 'Tests';
end;

function IsClass(const ASymbol: TIndexSymbol): Boolean;
begin
  Result := (ASymbol.Kind = TIndexSymbolKind.ClassType) and (ASymbol.Container = '');
end;

class function TTestUnits.ClassAt(const AUnit: TUnitIndex; ALine: Integer): string;
var
  Symbol, Last: TIndexSymbol;
  Found: Boolean;
begin
  Result := '';
  for Symbol in AUnit.Symbols do
    if IsClass(Symbol) and (Symbol.Range.StartPos.Line <= ALine) and (Symbol.Range.EndPos.Line >= ALine) then
      Exit(Symbol.Name);
  // Im implementation-Teil: die letzte Routine, die vor der Zeile beginnt.
  Found := False;
  Last := Default(TIndexSymbol);
  for Symbol in AUnit.Symbols do
    if not Symbol.InInterface and (Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_,
      TIndexSymbolKind.Routine]) and (Symbol.Range.StartPos.Line <= ALine) and
      (not Found or (Symbol.Range.StartPos.Line > Last.Range.StartPos.Line)) then
    begin
      Last := Symbol;
      Found := True;
    end;
  if Found and (Last.Kind <> TIndexSymbolKind.Routine) then
    for Symbol in AUnit.Symbols do
      if IsClass(Symbol) and SameText(Symbol.Name, Last.Container) then
        Exit(Symbol.Name);
end;

class function TTestUnits.FirstClass(const AUnit: TUnitIndex): string;
var
  Symbol: TIndexSymbol;
begin
  Result := '';
  for Symbol in AUnit.Symbols do
    if IsClass(Symbol) and Symbol.InInterface then
      Exit(Symbol.Name);
end;

class function TTestUnits.TestMethods(const AUnit: TUnitIndex; const AClassName: string): TArray<TTestUnitMethod>;
var
  Symbol: TIndexSymbol;
  Method: TTestUnitMethod;
  Count, Index: Integer;
  Wanted: Boolean;
begin
  Result := nil;
  for Symbol in AUnit.Symbols do
  begin
    if not Symbol.InInterface then
      Continue;
    if AClassName <> '' then
      Wanted := (Symbol.Kind = TIndexSymbolKind.Method) and SameText(Symbol.Container, AClassName) and
        (Symbol.Visibility in [TIndexVisibility.Public, TIndexVisibility.Published]) and
        not SameText(Symbol.Name, 'Destroy')
    else
      Wanted := (Symbol.Kind = TIndexSymbolKind.Routine) and (Symbol.Container = '');
    if not Wanted then
      Continue;
    // Überladene Methoden: TestBerechne, TestBerechne2, …
    Count := 1;
    for Index := 0 to High(Result) do
      if SameText(Result[Index].Target, Symbol.QualifiedName) then
        Inc(Count);
    Method.Target := Symbol.QualifiedName;
    Method.Name := 'Test' + Symbol.Name;
    if Count > 1 then
      Method.Name := Method.Name + IntToStr(Count);
    Result := Result + [Method];
  end;
end;

const
  ComponentAncestors: array[0..8] of string = ('TComponent', 'TControl', 'TWinControl', 'TCustomControl',
    'TGraphicControl', 'TForm', 'TFrame', 'TDataModule', 'TCustomForm');

class function TTestUnits.CreateExpression(const AUnit: TUnitIndex; const AClassName: string): string;
var
  Symbol: TIndexSymbol;
  HasConstructor: Boolean;
begin
  Result := '';
  HasConstructor := False;
  for Symbol in AUnit.Symbols do
  begin
    if IsClass(Symbol) and SameText(Symbol.Name, AClassName) then
    begin
      if Symbol.TypeParams <> '' then
        Exit('');
      // Ohne eigenen Konstruktor: der des Vorfahren; bei Komponenten mit Owner.
      if (Length(Symbol.Ancestors) > 0) and MatchText(Symbol.Ancestors[0], ComponentAncestors) then
        Result := AClassName + '.Create(nil)';
    end;
    if (Symbol.Kind <> TIndexSymbolKind.Constructor_) or not SameText(Symbol.Container, AClassName) or
      not Symbol.InInterface then
      Continue;
    HasConstructor := True;
    if not (Symbol.Visibility in [TIndexVisibility.Public, TIndexVisibility.Published]) then
      Continue;
    if Symbol.MinArgs = 0 then
    begin
      if SameText(Symbol.Name, 'Create') then
        Exit(AClassName + '.Create');
      Exit(AClassName + '.' + Symbol.Name);
    end;
    if (Symbol.MinArgs = 1) and (Length(Symbol.ParamTypes) > 0) and
      MatchText(Symbol.ParamTypes[0], ['TComponent', 'TObject']) then
      Exit(AClassName + '.' + Symbol.Name + '(nil)');
  end;
  if HasConstructor then
    Exit('');
  if Result = '' then
    Result := AClassName + '.Create';
end;

class function TTestUnits.UnitText(const ATestUnitName: string; const AUnit: TUnitIndex;
  const AClassName: string; const ALineBreak: string): string;
var
  Fixture, CreateText: string;
  Methods: TArray<TTestUnitMethod>;
  Method: TTestUnitMethod;
  Builder: TStringBuilder;
  Generic: Boolean;
  Symbol: TIndexSymbol;

  procedure Line(const AText: string);
  begin
    Builder.Append(AText).Append(ALineBreak);
  end;

begin
  Fixture := FixtureName(AClassName, AUnit.UnitName);
  Methods := TestMethods(AUnit, AClassName);
  Generic := False;
  for Symbol in AUnit.Symbols do
    if IsClass(Symbol) and SameText(Symbol.Name, AClassName) and (Symbol.TypeParams <> '') then
      Generic := True;
  CreateText := '';
  if AClassName <> '' then
    CreateText := CreateExpression(AUnit, AClassName);
  Builder := TStringBuilder.Create;
  try
    Line('unit ' + ATestUnitName + ';');
    Line('');
    Line('interface');
    Line('');
    Line('uses');
    Line('  DUnitX.TestFramework,');
    Line('  ' + AUnit.UnitName + ';');
    Line('');
    Line('type');
    Line('  [TestFixture]');
    Line('  ' + Fixture + ' = class');
    if (AClassName <> '') and not Generic then
    begin
      Line('  private');
      Line('    FSubject: ' + AClassName + ';');
    end;
    Line('  public');
    Line('    [Setup]');
    Line('    procedure Setup;');
    Line('    [TearDown]');
    Line('    procedure TearDown;');
    for Method in Methods do
    begin
      Line('    [Test]');
      Line('    procedure ' + Method.Name + ';');
    end;
    Line('  end;');
    Line('');
    Line('implementation');
    Line('');
    Line('procedure ' + Fixture + '.Setup;');
    Line('begin');
    if (AClassName <> '') and not Generic then
    begin
      if CreateText <> '' then
        Line('  FSubject := ' + CreateText + ';')
      else
        Line('  // ' + AClassName + ' braucht Argumente im Konstruktor: FSubject hier anlegen.');
    end
    else if Generic then
      Line('  // ' + AClassName + ' ist generisch: Objekt mit konkreten Typargumenten im Test anlegen.');
    Line('end;');
    Line('');
    Line('procedure ' + Fixture + '.TearDown;');
    Line('begin');
    if (AClassName <> '') and not Generic then
    begin
      Line('  FSubject.Free;');
      Line('  FSubject := nil;');
    end;
    Line('end;');
    for Method in Methods do
    begin
      Line('');
      Line('procedure ' + Fixture + '.' + Method.Name + ';');
      Line('begin');
      Line('  Assert.Fail(' + QuotedStr('Test für ' + Method.Target + ' fehlt noch') + ');');
      Line('end;');
    end;
    Line('');
    Line('initialization');
    Line('  TDUnitX.RegisterTestFixture(' + Fixture + ');');
    Line('');
    Line('end.');
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TTestUnits.IsTestProgram(const AText: string): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Index: Integer;
begin
  Tokens := TPascalLexer.Tokenize(AText);
  Result := False;
  for Index := 0 to High(Tokens) do
    if Tokens[Index].IsKeyword('program') then
      Exit(TUsesClauses.IsTestUnit(Tokens))
    else if Tokens[Index].IsKeyword('unit') or Tokens[Index].IsKeyword('library') or
      Tokens[Index].IsKeyword('package') then
      Exit(False);
end;

class function TTestUnits.FindTestProgram(const ACandidates: TArray<string>;
  const AReadText: TTestUnitReadText): string;
var
  Candidate: string;
begin
  Result := '';
  for Candidate in ACandidates do
    if SameText(ExtractFileExt(Candidate), '.dpr') and IsTestProgram(AReadText(Candidate)) then
      Exit(Candidate);
end;

function SplitPath(const APath: string): TArray<string>;
var
  Part: string;
begin
  Result := nil;
  for Part in StringReplace(APath, '/', '\', [rfReplaceAll]).Split(['\']) do
    if (Part <> '') and (Part <> '.') then
      Result := Result + [Part];
end;

class function TTestUnits.RelativePath(const ABaseDir, AFileName: string): string;
var
  Base, Target: TArray<string>;
  Common, Index: Integer;
begin
  Base := SplitPath(ABaseDir);
  Target := SplitPath(AFileName);
  Common := 0;
  while (Common < Length(Base)) and (Common < Length(Target) - 1) and SameText(Base[Common], Target[Common]) do
    Inc(Common);
  // Anderes Laufwerk (oder kein gemeinsamer Anfang bei absoluten Pfaden): vollständiger Pfad.
  if (Common = 0) and (Length(Base) > 0) and (Length(Target) > 0) and (Pos(':', Target[0]) > 0) then
    Exit(StringReplace(AFileName, '/', '\', [rfReplaceAll]));
  Result := '';
  for Index := Common to High(Base) do
    Result := Result + '..\';
  for Index := Common to High(Target) do
  begin
    Result := Result + Target[Index];
    if Index < High(Target) then
      Result := Result + '\';
  end;
end;

end.
