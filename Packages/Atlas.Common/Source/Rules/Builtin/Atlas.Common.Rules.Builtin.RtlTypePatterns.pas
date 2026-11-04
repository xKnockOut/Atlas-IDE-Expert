unit Atlas.Common.Rules.Builtin.RtlTypePatterns;

// Regeln für fehleranfällige RTL-Muster, Stufe 2 aus #153 (mit deklarierten
// Typen aus der Datei, Atlas.Common.Pascal.DeclaredTypes):
//   int32-mul-overflow       Int64 := Int32 * Int32 läuft vor der Zuweisung über
//   sizeof-pointer           Move/FillChar mit SizeOf eines Zeigers, Strings oder dynamischen Arrays
//   char-to-pchar            Cast eines Char nach PChar
//   float-equality           Gleitkommavergleich mit = oder <> (nicht mit 0, nicht in Equals-Vergleichern)
//   constructor-on-instance  Konstruktor auf einer Variablen statt auf der Klasse
//   format-without-settings  Format mit %f/%n/%m/%g/%e, FloatToStr, StrToDate … ohne TFormatSettings
//                            (FormatDateTime/FormatFloat mit festem Bild nur, wenn es Trennzeichen
//                            wie : / . , enthält)
//   managed-type-raw-memory  FillChar, ZeroMemory, Move, CopyMemory, GetMem oder FreeMem auf Variablen,
//                            deren Typ Strings, Interfaces, dynamische Arrays oder Variants enthält
//                            (#921). Records und Aliasse werden in der Datei und im Index aufgelöst.
//   threadvar-managed        threadvar mit verwaltetem Typ: Delphi finalisiert ihn am Thread-Ende
//                            nicht (#922)
//   pchar-of-temporary       PChar(S + '.bak'), PChar(IntToStr(N)) … in einer Variablen, einem Feld oder
//                            Result gemerkt bzw. an PostMessage übergeben (#923): der temporäre String
//                            ist nach der Anweisung weg
//   stringlist-unsorted      Find oder Duplicates := dupIgnore/dupError auf einer TStringList, die in der
//                            Datei erzeugt, aber nie sortiert wird (#925)
//   writeln-in-gui-app       Write, Writeln, Read oder Readln auf die Standardein- oder -ausgabe in einem
//                            Programm ohne Konsole (#926): E/A-Fehler 104 bzw. 105 zur Laufzeit
//   unchecked-conversion     StrToInt, StrToFloat, StrToDate … direkt auf Edit.Text, Cells[…] oder Lines[…]
//                            ohne umgebendes try/except (#932); Korrektur: TryStrToInt … mit raise im
//                            Fehlerzweig, wenn das Ziel eine Variable des passenden Typs ist
//   dictionary-get-without-check
//                            Dict[Key] bzw. Dict.Items[Key] gelesen, ohne dass ContainsKey oder TryGetValue
//                            denselben Schlüssel vorher in der Routine geprüft hat (#933). Still bleibt die
//                            Regel, wenn die Routine das Dictionary vorher selbst füllt (Add, AddOrSetValue,
//                            Dict[K] := …) oder der Schlüssel aus Keys stammt (for K in Dict.Keys,
//                            Namen := Dict.Keys.ToArray). Felder, die die Unit an anderer Stelle füllt, sichert
//                            die Klasse selbst (#1109). Korrektur: TryGetValue mit Vorgabewert
//   delimited-text-without-strict
//                            Liste.DelimitedText := … nach Liste.Delimiter := … in derselben Routine, ohne dass
//                            StrictDelimiter gesetzt wird (#952; bei Feldern in der ganzen Unit): DelimitedText
//                            trennt dann auch an Leerzeichen. Korrektur: StrictDelimiter := True; davor
//   unchecked-enum-cast      TStatus(Zahl) mit einem Aufzählungstyp aus Datei oder Index, wenn die Zahl aus einer
//                            Quelle der Option "sources" stammt (FieldByName, ReadInteger, AsInteger, StrToInt):
//                            direkt im Argument oder über eine Variable, die zwischen Zuweisung und Umwandlung
//                            nicht gelesen (geprüft) wird (#954). EnsureRange/Min/Max im Argument gelten als
//                            Prüfung. Korrektur bei direkter Quelle: Hilfsvariable, InRange-Prüfung mit raise
//                            EConvertError davor, System.Math in uses
//   createprocess-readonly-commandline
//                            CreateProcess(W) bzw. CreateProcessAsUser(W) mit PChar(…) als Befehlszeile, die auf
//                            schreibgeschützten Speicher zeigen kann (#955): Literal oder Konstante, Verkettung aus
//                            genau einem Literal und einem Wert (ist er leer, bleibt das Literal), eine Variable mit
//                            einer solchen letzten Zuweisung ohne UniqueString danach, ein String-Parameter (mittlere
//                            Konfidenz). CreateProcessW schreibt in den Puffer. Korrektur: lokale Kopie mit
//                            UniqueString bzw. UniqueString(Variable) vor der Anweisung
//   global-formatsettings-modified
//                            Zuweisung an die globale FormatSettings oder eines ihrer Felder, auch an die veralteten
//                            globalen Variablen DecimalSeparator, ShortDateFormat … (#1089): ändert die Formatierung
//                            für die ganze Anwendung, alle Packages im Prozess (im IDE-Plugin die IDE) und alle
//                            Threads. Gemeldet wird nur, wenn der Name sicher die Variable aus System.SysUtils ist:
//                            keine lokale Deklaration, kein Mitglied der Klasse und ihrer Vorfahren (bricht die Kette
//                            an einem unbekannten Vorfahren ab, schweigt die Regel), kein with. Korrektur bei genau
//                            einer solchen Zuweisung in der Routine und Formatierungsaufrufen danach: lokale
//                            TFormatSettings (TFormatSettings.Invariant für DecimalSeparator := '.', sonst eine
//                            Kopie mit dem geänderten Feld) an diese Aufrufe übergeben. Option allowInProgram
//                            erlaubt die Zuweisungen in der .dpr
// Bezeichner, deren Typ in der Datei nicht deklariert ist, lösen keinen Treffer aus.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TInt32MulOverflowRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TSizeOfPointerRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TCharToPCharRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TFloatEqualityRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TConstructorOnInstanceRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TFormatWithoutSettingsRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Enthält AFormat einen vom Gebietsschema abhängigen Platzhalter (%f, %n, %m, %g, %e)?</summary>
    class function HasLocaleSpecifier(const AFormat: string): Boolean; static;
    /// <summary>Hängt das Bild APicture von FormatDateTime bzw. FormatFloat/FormatCurr (AFunction) vom
    /// Gebietsschema ab? Nur die Trennzeichen außerhalb von Anführungszeichen tun es: ":" und "/" werden zu
    /// TimeSeparator und DateSeparator, "." und "," zu DecimalSeparator und ThousandSeparator. Ziffernfelder
    /// ('yyyy"-"mm"-"dd') sind fest; Namen und Gesamtformate ('ddddd t', 'mmmm') verlangen das Gebietsschema
    /// ausdrücklich (#1109).</summary>
    class function PictureDependsOnLocale(const AFunction, APicture: string): Boolean; static;
  end;

  TManagedTypeRawMemoryRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TThreadvarManagedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TPCharOfTemporaryRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TStringListUnsortedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TWritelnInGuiAppRule = class(TInterfacedObject, IRule)
  public const
    DefaultReplacement = 'OutputDebugString';
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Anwendungsart aus DCC_ConsoleTarget der .dproj und dem Text der .dpr: Console bei
    /// "true" oder {$APPTYPE CONSOLE}, Service bei einem program mit Vcl.SvcMgr und ohne Vcl.Forms,
    /// sonst Gui bei einem program; Library_ bei einer library ohne Formulare und ohne Vcl.Forms,
    /// Package bei einem package, sonst Unknown (DLL mit Formularen, kein Text).</summary>
    class function ApplicationKind(const AConsoleTarget, AMainSource: string): TRuleApplicationKind; static;
    /// <summary>Option "replacement" aus den Regeloptionen; ohne Angabe OutputDebugString.</summary>
    class function Replacement(const AOptions: string): string; static;
  end;

  TUncheckedConversionRule = class(TInterfacedObject, IRule)
  public const
    DefaultFunctions: array[0..5] of string = ('StrToInt', 'StrToInt64', 'StrToFloat', 'StrToDate', 'StrToDateTime',
      'StrToCurr');
    DefaultSources: array[0..2] of string = ('Text', 'Cells', 'Lines');
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TDictionaryGetWithoutCheckRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Registriert die typbasierten Regeln für RTL-Muster.</summary>
  TDelimitedTextWithoutStrictRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TCreateProcessReadonlyCommandLineRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Stelle der Befehlszeile (ab 0) bei CreateProcess, CreateProcessW, CreateProcessAsUser(W); -1 sonst.
    /// </summary>
    class function CommandLineIndex(const AName: string): Integer; static;
  end;

  TUncheckedEnumCastRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Herkunft für die Meldung: "aus der Datenbank", "aus einem Text" …</summary>
    class function Origin(const ASource: string): string; static;
  end;

  TGlobalFormatSettingsModifiedRule = class(TInterfacedObject, IRule)
  public const
    /// <summary>Veraltete globale Variablen aus System.SysUtils (bis XE5), gleichnamig mit den Feldern von
    /// TFormatSettings.</summary>
    DeprecatedGlobals: array[0..19] of string = ('CurrencyString', 'CurrencyFormat', 'NegCurrFormat',
      'ThousandSeparator', 'DecimalSeparator', 'CurrencyDecimals', 'DateSeparator', 'ShortDateFormat',
      'LongDateFormat', 'TimeSeparator', 'TimeAMString', 'TimePMString', 'ShortTimeFormat', 'LongTimeFormat',
      'ShortMonthNames', 'LongMonthNames', 'ShortDayNames', 'LongDayNames', 'ListSeparator',
      'TwoDigitYearCenturyWindow');
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Was die Zuweisung an das Feld AField ändert, für die Meldung ("den Dezimaltrenner");
    /// AField = '' steht für die ganze FormatSettings.</summary>
    class function Subject(const AField: string): string; static;
  end;

procedure RegisterRtlTypePatternRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Pascal.FormatStrings,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.ManagedTypes,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Text.Lines;

type
  TTokens = TArray<TPascalToken>;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function NextCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
  begin
    Inc(Result);
  end;
end;

function PreviousCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
  begin
    Dec(Result);
  end;
end;

function Closing(const ATokens: TTokens; AOpen: Integer): Integer;
var
  Depth: Integer;
begin
  Depth := 0;
  for Result := AOpen to High(ATokens) do
  begin
    if ATokens[Result].IsSymbol('(') or ATokens[Result].IsSymbol('[') then
    begin
      Inc(Depth);
    end
    else if ATokens[Result].IsSymbol(')') or ATokens[Result].IsSymbol(']') then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        Exit;
      end;
    end;
  end;
  Result := -1;
end;

/// <summary>Zahl der Argumente auf oberster Ebene zwischen AOpen und AClose.</summary>
function ArgumentCount(const ATokens: TTokens; AOpen, AClose: Integer): Integer;
var
  Index, Depth: Integer;
begin
  if NextCode(ATokens, AOpen + 1) = AClose then
  begin
    Exit(0);
  end;
  Result := 1;
  Depth := 0;
  for Index := AOpen + 1 to AClose - 1 do
  begin
    if ATokens[Index].IsSymbol('(') or ATokens[Index].IsSymbol('[') then
    begin
      Inc(Depth);
    end
    else if ATokens[Index].IsSymbol(')') or ATokens[Index].IsSymbol(']') then
    begin
      Dec(Depth);
    end
    else if (Depth = 0) and ATokens[Index].IsSymbol(',') then
    begin
      Inc(Result);
    end;
  end;
end;

function RangeOf(const ATokens: TTokens; AFirst, ALast: Integer): TTextRange;
begin
  Result := TTextRange.Create(ATokens[AFirst].StartPos, ATokens[ALast].EndPos);
end;

/// <summary>Einfacher Bezeichner: kein Teil einer Kette A.B und kein Aufruf.</summary>
function IsPlainIdentifier(const ATokens: TTokens; AIndex: Integer): Boolean;
var
  Prev, Next: Integer;
begin
  if (AIndex < 0) or (AIndex > High(ATokens)) or (ATokens[AIndex].Kind <> TPascalTokenKind.Identifier) then
  begin
    Exit(False);
  end;
  Prev := PreviousCode(ATokens, AIndex);
  Next := NextCode(ATokens, AIndex + 1);
  Result := not ((Prev >= 0) and (ATokens[Prev].IsSymbol('.') or ATokens[Prev].IsSymbol('@'))) and
    not ((Next <= High(ATokens)) and (ATokens[Next].IsSymbol('.') or ATokens[Next].IsSymbol('(') or
    ATokens[Next].IsSymbol('[') or ATokens[Next].IsSymbol('^')));
end;

/// <summary>Liegt APosition im Rumpf (begin … end) einer Routine?</summary>
function InStatements(ATree: TSyntaxTree; const APosition: TTextPosition): Boolean;
var
  Root: TSyntaxNode;
  Position: TTextPosition;
begin
  Root := ATree.Root;
  if Root = nil then
  begin
    Exit(False);
  end;
  Position := APosition;
  // Iterativ (Bericht M1). Die Wurzel selbst zählt wie früher nicht.
  Result := Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode.Kind = TSyntaxKind.Block) and (ANode <> Root) and
        ((ANode.StartPos.Line < Position.Line) or ((ANode.StartPos.Line = Position.Line) and
        (ANode.StartPos.Character <= Position.Character))) and
        ((ANode.EndPos.Line > Position.Line) or ((ANode.EndPos.Line = Position.Line) and
        (ANode.EndPos.Character > Position.Character))) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

{ TInt32MulOverflowRule }

function TInt32MulOverflowRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('int32-mul-overflow', TRuleSeverity.Warning,
    'Int32-Multiplikation läuft vor der Zuweisung an Int64 über');
end;

procedure TInt32MulOverflowRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Types: TDeclaredTypes;
  Index, Target, Left, Times, Right, Stop: Integer;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for Index := 0 to High(Tokens) do
    begin
      // V := A * B; mit V: Int64 und A, B höchstens 32 Bit.
      if not Tokens[Index].IsSymbol(':=') then
      begin
        Continue;
      end;
      Target := PreviousCode(Tokens, Index);
      Left := NextCode(Tokens, Index + 1);
      Times := NextCode(Tokens, Left + 1);
      Right := NextCode(Tokens, Times + 1);
      Stop := NextCode(Tokens, Right + 1);
      if (Stop > High(Tokens)) or not Tokens[Times].IsSymbol('*') or not IsPlainIdentifier(Tokens, Target) or
        not IsPlainIdentifier(Tokens, Left) or not (IsPlainIdentifier(Tokens, Right) or
        (Tokens[Right].Kind = TPascalTokenKind.Number)) or
        not (Tokens[Stop].IsSymbol(';') or Tokens[Stop].IsKeyword('end') or Tokens[Stop].IsKeyword('else')) then
      begin
        Continue;
      end;
      if not TDeclaredTypes.IsInt64(Types.DeclaredType(Tokens[Target].Text, Tokens[Target].StartPos)) or
        not TDeclaredTypes.IsInt32(Types.DeclaredType(Tokens[Left].Text, Tokens[Left].StartPos)) or
        not ((Tokens[Right].Kind = TPascalTokenKind.Number) or
        TDeclaredTypes.IsInt32(Types.DeclaredType(Tokens[Right].Text, Tokens[Right].StartPos))) then
      begin
        Continue;
      end;
      AReport.Add(RangeOf(Tokens, Left, Right), Format('%s * %s wird in 32 Bit gerechnet und läuft über, bevor ' +
        'das Ergebnis in %s (Int64) landet', [Tokens[Left].Text, Tokens[Right].Text, Tokens[Target].Text]),
        TRuleConfidence.High, [TRuleFix.Create('Operand nach Int64 umwandeln',
        [TRuleEdit.Create(RangeOf(Tokens, Left, Left), 'Int64(' + Tokens[Left].Text + ')')], True)]);
    end;
  finally
    Types.Free;
  end;
end;

{ TSizeOfPointerRule }

function TSizeOfPointerRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('sizeof-pointer', TRuleSeverity.Error,
    'Move/FillChar mit SizeOf eines Zeigers statt der Daten');
end;

procedure TSizeOfPointerRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Types: TDeclaredTypes;
  Index, Open, Close, Inner, SizeOpen, Name, SizeClose: Integer;
  TypeName: string;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for Index := 0 to High(Tokens) do
    begin
      if not ((Tokens[Index].Kind = TPascalTokenKind.Identifier) and
        MatchText(Tokens[Index].Text, ['Move', 'FillChar', 'ZeroMemory', 'CopyMemory', 'FillMemory'])) then
      begin
        Continue;
      end;
      Open := NextCode(Tokens, Index + 1);
      if (Open > High(Tokens)) or not Tokens[Open].IsSymbol('(') then
      begin
        Continue;
      end;
      Close := Closing(Tokens, Open);
      for Inner := Open + 1 to Close - 1 do
      begin
        if not SameText(Tokens[Inner].Text, 'SizeOf') then
        begin
          Continue;
        end;
        SizeOpen := NextCode(Tokens, Inner + 1);
        Name := NextCode(Tokens, SizeOpen + 1);
        SizeClose := NextCode(Tokens, Name + 1);
        if (SizeClose >= Close) or not Tokens[SizeOpen].IsSymbol('(') or not Tokens[SizeClose].IsSymbol(')') or
          (Tokens[Name].Kind <> TPascalTokenKind.Identifier) then
        begin
          Continue;
        end;
        TypeName := Types.DeclaredType(Tokens[Name].Text, Tokens[Name].StartPos);
        if (TypeName <> '') and TDeclaredTypes.IsReference(TypeName) then
        begin
          AReport.Add(RangeOf(Tokens, Inner, SizeClose), Format('SizeOf(%s) ist die Größe des Zeigers (%s), ' +
            'nicht die der Daten; Length(…) * SizeOf(Element) verwenden', [Tokens[Name].Text, TypeName]),
            TRuleConfidence.High);
        end;
      end;
    end;
  finally
    Types.Free;
  end;
end;

{ TCharToPCharRule }

function TCharToPCharRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('char-to-pchar', TRuleSeverity.Error, 'Char wird nach PChar umgewandelt');
end;

procedure TCharToPCharRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Types: TDeclaredTypes;
  Index, Open, Name, Close: Integer;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for Index := 0 to High(Tokens) do
    begin
      if not ((Tokens[Index].Kind = TPascalTokenKind.Identifier) and
        MatchText(Tokens[Index].Text, ['PChar', 'PWideChar', 'PAnsiChar'])) then
      begin
        Continue;
      end;
      Open := NextCode(Tokens, Index + 1);
      Name := NextCode(Tokens, Open + 1);
      Close := NextCode(Tokens, Name + 1);
      if (Close > High(Tokens)) or not Tokens[Open].IsSymbol('(') or not Tokens[Close].IsSymbol(')') or
        (Tokens[Name].Kind <> TPascalTokenKind.Identifier) then
      begin
        Continue;
      end;
      if TDeclaredTypes.IsChar(Types.DeclaredType(Tokens[Name].Text, Tokens[Name].StartPos)) then
      begin
        AReport.Add(RangeOf(Tokens, Index, Close), Format('%s(%s) macht aus dem Zeichen eine Adresse; ' +
          'gemeint ist meist ein String: %s(string(%s))', [Tokens[Index].Text, Tokens[Name].Text,
          Tokens[Index].Text, Tokens[Name].Text]), TRuleConfidence.High);
      end;
    end;
  finally
    Types.Free;
  end;
end;

{ TFloatEqualityRule }

function TFloatEqualityRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('float-equality', TRuleSeverity.Hint, 'Gleitkommavergleich mit = oder <>');
end;

function IsZero(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind = TPascalTokenKind.Number) and MatchStr(AToken.Text, ['0', '0.0', '0.00']);
end;

/// <summary>Gleitkommatyp, für den ein exakter Vergleich verdächtig ist. Datum und Uhrzeit nicht: Zeitstempel
/// (z. B. Dateizeiten) werden absichtlich exakt verglichen (#647).</summary>
function IsInexact(const AType: string): Boolean;
begin
  Result := TDeclaredTypes.IsFloat(AType) and not MatchText(AType, ['TDateTime', 'TDate', 'TTime']);
end;

/// <summary>
/// Steht vor ATokens[AIndex] in derselben Routine "AName := Max(…)" bzw. Min(…) mit AOther unter den Argumenten?
/// Dann ist AName genau einer der Werte, und = AOther ist ein exakter Vergleich (MaxValue = R, #1109).
/// </summary>
function SelectedFrom(const ATokens: TTokens; AIndex: Integer; const AName, AOther: string): Boolean;
var
  Index, Call, Close, Inner: Integer;
begin
  Result := False;
  Index := AIndex - 1;
  while (Index >= 0) and not (ATokens[Index].IsKeyword('procedure') or ATokens[Index].IsKeyword('function') or
    ATokens[Index].IsKeyword('constructor') or ATokens[Index].IsKeyword('destructor')) do
  begin
    if (ATokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(ATokens[Index].Text, AName) then
    begin
      Call := NextCode(ATokens, NextCode(ATokens, Index + 1) + 1);
      if (Call <= High(ATokens)) and ATokens[NextCode(ATokens, Index + 1)].IsSymbol(':=') and
        MatchText(ATokens[Call].Text, ['Max', 'Min']) then
      begin
        Close := NextCode(ATokens, Call + 1);
        if (Close <= High(ATokens)) and ATokens[Close].IsSymbol('(') then
        begin
          for Inner := Close + 1 to High(ATokens) do
          begin
            if ATokens[Inner].IsSymbol(';') then
            begin
              Break;
            end;
            if (ATokens[Inner].Kind = TPascalTokenKind.Identifier) and SameText(ATokens[Inner].Text, AOther) then
            begin
              Exit(True);
            end;
          end;
        end;
        // Die letzte Zuweisung zählt.
        Exit;
      end;
    end;
    Dec(Index);
  end;
end;

/// <summary>Steht AOffset im Rumpf eines Gleichheitsvergleichers (Equals, Equals_Double, class operator Equal,
/// NotEqual, IsEqual)? Dort ist der exakte Vergleich Vertrag: Equals muss zu GetHashCode passen
/// (System.Generics.Defaults), eine Toleranz wäre nicht transitiv.</summary>
function InEqualityRoutine(ATree: TSyntaxTree; AOffset: Integer): Boolean;
var
  mRoutine: TSyntaxNode;
  mName: string;
begin
  mRoutine := TRoutineBody.RoutineAt(ATree, AOffset);
  if mRoutine = nil then
  begin
    Exit(False);
  end;
  mName := mRoutine.Name;
  if Pos('.', mName) > 0 then
  begin
    mName := Copy(mName, LastDelimiter('.', mName) + 1, MaxInt);
  end;
  Result := StartsText('Equal', mName) or MatchText(mName, ['NotEqual', 'IsEqual']);
end;

procedure TFloatEqualityRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Types: TDeclaredTypes;
  Index, Left, Right, Prev, Next: Integer;
  IsFloat: Boolean;
  Call: string;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for Index := 0 to High(Tokens) do
    begin
      if not (Tokens[Index].IsSymbol('=') or Tokens[Index].IsSymbol('<>')) then
      begin
        Continue;
      end;
      Left := PreviousCode(Tokens, Index);
      Right := NextCode(Tokens, Index + 1);
      if (Left < 0) or (Right > High(Tokens)) or not InStatements(AContext.Tree, Tokens[Index].StartPos) then
      begin
        Continue;
      end;
      // Nur einfache Operanden: A = B, A <> 1.5; nicht Teil eines größeren Ausdrucks davor oder danach.
      Prev := PreviousCode(Tokens, Left);
      Next := NextCode(Tokens, Right + 1);
      if not ((Tokens[Left].Kind = TPascalTokenKind.Number) or IsPlainIdentifier(Tokens, Left)) or
        not ((Tokens[Right].Kind = TPascalTokenKind.Number) or IsPlainIdentifier(Tokens, Right)) or
        ((Prev >= 0) and (Tokens[Prev].Kind = TPascalTokenKind.Symbol) and
        MatchStr(Tokens[Prev].Text, ['+', '-', '*', '/'])) or
        ((Next <= High(Tokens)) and (Tokens[Next].Kind = TPascalTokenKind.Symbol) and
        MatchStr(Tokens[Next].Text, ['+', '-', '*', '/'])) or IsZero(Tokens[Left]) or IsZero(Tokens[Right]) then
      begin
        Continue;
      end;
      IsFloat := ((Tokens[Left].Kind = TPascalTokenKind.Identifier) and
        IsInexact(Types.DeclaredType(Tokens[Left].Text, Tokens[Left].StartPos))) or
        ((Tokens[Right].Kind = TPascalTokenKind.Identifier) and
        IsInexact(Types.DeclaredType(Tokens[Right].Text, Tokens[Right].StartPos)));
      if not IsFloat or SelectedFrom(Tokens, Index, Tokens[Left].Text, Tokens[Right].Text) or
        SelectedFrom(Tokens, Index, Tokens[Right].Text, Tokens[Left].Text) or
        InEqualityRoutine(AContext.Tree, Tokens[Index].Offset) then
      begin
        Continue;
      end;
      Call := 'SameValue(' + Tokens[Left].Text + ', ' + Tokens[Right].Text + ')';
      if Tokens[Index].IsSymbol('<>') then
      begin
        Call := 'not ' + Call;
      end;
      AReport.Add(RangeOf(Tokens, Left, Right), 'Gleitkommawerte sind selten exakt gleich; SameValue aus ' +
        'System.Math mit Toleranz verwenden', TRuleConfidence.Medium,
        [TRuleFix.Create('SameValue verwenden', [TRuleEdit.Create(RangeOf(Tokens, Left, Right), Call)])]);
    end;
  finally
    Types.Free;
  end;
end;

{ TConstructorOnInstanceRule }

function TConstructorOnInstanceRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('constructor-on-instance', TRuleSeverity.Warning,
    'Konstruktor auf einer Instanz statt auf der Klasse');
end;

procedure TConstructorOnInstanceRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Types: TDeclaredTypes;
  Index, Dot, Ctor, Prev: Integer;
  TypeName: string;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for Index := 0 to High(Tokens) do
    begin
      if Tokens[Index].Kind <> TPascalTokenKind.Identifier then
      begin
        Continue;
      end;
      Prev := PreviousCode(Tokens, Index);
      Dot := NextCode(Tokens, Index + 1);
      Ctor := NextCode(Tokens, Dot + 1);
      if (Ctor > High(Tokens)) or not Tokens[Dot].IsSymbol('.') or not SameText(Tokens[Ctor].Text, 'Create') or
        ((Prev >= 0) and (Tokens[Prev].IsSymbol('.') or Tokens[Prev].IsKeyword('inherited'))) then
      begin
        Continue;
      end;
      TypeName := Types.DeclaredType(Tokens[Index].Text, Tokens[Index].StartPos);
      // Klassenreferenzen (TComponentClass, class of …) dürfen Create aufrufen.
      if (TypeName = '') or not StartsStr('T', TypeName) or EndsText('Class', TypeName) or
        StartsText('class', TypeName) or (Pos('<', TypeName) > 0) or not InStatements(AContext.Tree,
        Tokens[Index].StartPos) then
      begin
        Continue;
      end;
      AReport.Add(RangeOf(Tokens, Index, Ctor), Format('Create auf der Variablen %s statt auf der Klasse %s; ' +
        'das legt kein neues Objekt an', [Tokens[Index].Text, TypeName]), TRuleConfidence.High,
        [TRuleFix.Create(TypeName + '.Create verwenden', [TRuleEdit.Create(RangeOf(Tokens, Index, Index),
        TypeName)])]);
    end;
  finally
    Types.Free;
  end;
end;

{ TFormatWithoutSettingsRule }

function TFormatWithoutSettingsRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('format-without-settings', TRuleSeverity.Hint,
    'Formatierung abhängig vom Gebietsschema');
end;

class function TFormatWithoutSettingsRule.HasLocaleSpecifier(const AFormat: string): Boolean;
var
  mValue: string;
begin
  // Zerlegung gemeinsam mit format-args; ein Literal mit Hochkommas wird erst ausgewertet.
  if TFormatString.LiteralValue(AFormat, mValue) then
  begin
    Result := TFormatString.HasLocaleSpecifier(mValue);
  end
  else
  begin
    Result := TFormatString.HasLocaleSpecifier(AFormat);
  end;
end;

class function TFormatWithoutSettingsRule.PictureDependsOnLocale(const AFunction, APicture: string): Boolean;
var
  Index: Integer;
  Quote: Char;
  Separators: TSysCharSet;
begin
  if SameText(AFunction, 'FormatDateTime') then
  begin
    Separators := [':', '/'];
  end
  else
  begin
    Separators := ['.', ','];
  end;
  Quote := #0;
  for Index := 1 to Length(APicture) do
  begin
    if Quote <> #0 then
    begin
      if APicture[Index] = Quote then
      begin
        Quote := #0;
      end;
    end
    else if CharInSet(APicture[Index], ['"', '''']) then
    begin
      Quote := APicture[Index];
    end
    else if CharInSet(APicture[Index], Separators) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Zahl der Argumente ohne TFormatSettings; 0, wenn AName keine solche Funktion ist.</summary>
function PlainArgumentCount(const AName: string): Integer;
const
  One: array[0..10] of string = ('FloatToStr', 'StrToFloat', 'DateToStr', 'StrToDate', 'DateTimeToStr',
    'StrToDateTime', 'TimeToStr', 'StrToTime', 'CurrToStr', 'StrToCurr', 'TextToFloat');
  Two: array[0..8] of string = ('FormatFloat', 'FormatDateTime', 'TryStrToFloat', 'StrToFloatDef',
    'TryStrToDate', 'StrToDateDef', 'TryStrToDateTime', 'StrToDateTimeDef', 'FormatCurr');
begin
  if MatchText(AName, One) then
  begin
    Result := 1;
  end
  else if MatchText(AName, Two) then
  begin
    Result := 2;
  end
  else if SameText(AName, 'FloatToStrF') then
  begin
    Result := 4;
  end
  else
  begin
    Result := 0;
  end;
end;

/// <summary>Formatierungsaufruf ohne TFormatSettings bei AIndex (Format mit %f/%n/%m/%g/%e, FloatToStr, StrToDate
/// …); AClose ist dann die schließende Klammer.</summary>
function IsLocaleCall(const ATokens: TTokens; AIndex: Integer; out AClose: Integer): Boolean;
var
  Open, First, Prev: Integer;
begin
  Result := False;
  AClose := -1;
  if ATokens[AIndex].Kind <> TPascalTokenKind.Identifier then
  begin
    Exit;
  end;
  Prev := PreviousCode(ATokens, AIndex);
  Open := NextCode(ATokens, AIndex + 1);
  // Methoden wie Writer.Format bleiben außen vor; SysUtils.Format zählt.
  if (Open > High(ATokens)) or not ATokens[Open].IsSymbol('(') or ((Prev >= 0) and ATokens[Prev].IsSymbol('.') and
    not ((PreviousCode(ATokens, Prev) >= 0) and MatchText(ATokens[PreviousCode(ATokens, Prev)].Text,
    ['SysUtils', 'System.SysUtils']))) then
  begin
    Exit;
  end;
  AClose := Closing(ATokens, Open);
  if AClose < 0 then
  begin
    Exit;
  end;
  if SameText(ATokens[AIndex].Text, 'Format') then
  begin
    First := NextCode(ATokens, Open + 1);
    Result := (ArgumentCount(ATokens, Open, AClose) = 2) and
      (ATokens[First].Kind = TPascalTokenKind.StringLiteral) and
      TFormatWithoutSettingsRule.HasLocaleSpecifier(ATokens[First].Text);
  end
  else
  begin
    Result := (PlainArgumentCount(ATokens[AIndex].Text) > 0) and
      (ArgumentCount(ATokens, Open, AClose) = PlainArgumentCount(ATokens[AIndex].Text));
    // Festes Bild als einzelnes Literal: nur seine Trennzeichen hängen vom Gebietsschema ab.
    First := NextCode(ATokens, Open + 1);
    if Result and MatchText(ATokens[AIndex].Text, ['FormatDateTime', 'FormatFloat', 'FormatCurr']) and
      (ATokens[First].Kind = TPascalTokenKind.StringLiteral) and ATokens[NextCode(ATokens, First + 1)].IsSymbol(',')
      then
    begin
      Result := TFormatWithoutSettingsRule.PictureDependsOnLocale(ATokens[AIndex].Text,
        StringReplace(Copy(ATokens[First].Text, 2, Length(ATokens[First].Text) - 2), '''''', '''', [rfReplaceAll]));
    end;
  end;
end;

/// <summary>Steht vor dem Namen an AIndex ein Punkt (SysUtils.Format)?</summary>
function IsQualified(const ATokens: TTokens; AIndex: Integer): Boolean;
var
  mPrev: Integer;
begin
  mPrev := PreviousCode(ATokens, AIndex);
  Result := (mPrev >= 0) and ATokens[mPrev].IsSymbol('.');
end;

/// <summary>Rang von AUnitName unter den uses von AUnit, höchste Priorität zuerst (die letzten Einträge gewinnen,
/// implementation vor interface); -1, wenn die Unit nicht in uses steht.</summary>
function UsesRank(const AUnit: TUnitIndex; const AUnitNames: array of string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := High(AUnit.ImplementationUses) downto 0 do
  begin
    if MatchText(AUnit.ImplementationUses[mIndex], AUnitNames) then
    begin
      Exit(High(AUnit.ImplementationUses) - mIndex);
    end;
  end;
  for mIndex := High(AUnit.InterfaceUses) downto 0 do
  begin
    if MatchText(AUnit.InterfaceUses[mIndex], AUnitNames) then
    begin
      Exit(Length(AUnit.ImplementationUses) + High(AUnit.InterfaceUses) - mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Ruft der Name an AIndex eine eigene Routine statt der aus System.SysUtils auf? Aufgelöst wie vom
/// Compiler: lokale Routinen, Methoden der eigenen Klasse und Routinen der eigenen Unit verdecken die RTL, ebenso
/// eine Unit, die in uses nach System.SysUtils steht. Unbekannte Namen (ohne Index) gelten als RTL; ebenso eine
/// fremde Unit, wenn System.SysUtils in uses danach steht, aber nicht im Index ist.</summary>
function CallsOwnRoutine(const AContext: TRuleContext; var ACache: IRuleDerivedCache; const AToken: TPascalToken):
  Boolean;
var
  mResolved: TResolvedSymbol;
  mUnit: TUnitIndex;
  mOwnRank: Integer;
begin
  if ACache = nil then
  begin
    ACache := TRuleDerived.Open(AContext);
  end;
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mResolved := TRuleDerived.Resolver(ACache, AContext).ResolveChain(AContext.Tree, AContext.RelativePath,
    [AToken.Text], AToken.Offset, False);
  if (mResolved.Kind in [TResolvedKind.None, TResolvedKind.UnitName]) or
    MatchText(mResolved.UnitName, ['System.SysUtils', 'SysUtils']) then
  begin
    Exit(False);
  end;
  mUnit := TRuleDerived.UnitIndex(ACache, AContext);
  if (mResolved.Kind = TResolvedKind.Local) or (mResolved.Container <> '') or
    SameText(mResolved.UnitName, mUnit.UnitName) then
  begin
    Exit(True);
  end;
  mOwnRank := UsesRank(mUnit, [mResolved.UnitName]);
  Result := (mOwnRank < 0) or (UsesRank(mUnit, ['System.SysUtils', 'SysUtils']) < 0) or
    (mOwnRank < UsesRank(mUnit, ['System.SysUtils', 'SysUtils']));
end;

procedure TFormatWithoutSettingsRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Index, Close: Integer;
  mCache: IRuleDerivedCache;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mCache := nil;
  Tokens := AContext.Tree.Tokens;
  for Index := 0 to High(Tokens) do
  begin
    // Erst das Muster, dann die Auflösung: Eine eigene Routine gleichen Namens (auch aus einer anderen Unit) ist
    // nicht die aus System.SysUtils. SysUtils.Format ist ausdrücklich die RTL.
    if IsLocaleCall(Tokens, Index, Close) and (IsQualified(Tokens, Index) or
      not CallsOwnRoutine(AContext, mCache, Tokens[Index])) then
    begin
      AReport.Add(RangeOf(Tokens, Index, Close), Format('%s ohne TFormatSettings hängt vom Gebietsschema ab ' +
        '(Dezimaltrenner, Datumsformat); für Dateien und Protokolle eine feste TFormatSettings übergeben',
        [Tokens[Index].Text]), TRuleConfidence.Medium, [TRuleFix.Create('FormatSettings übergeben',
        [TRuleEdit.Create(TTextRange.Create(Tokens[Close].StartPos, Tokens[Close].StartPos),
        ', FormatSettings')])]);
    end;
  end;
end;

{ TManagedTypeRawMemoryRule }

function TManagedTypeRawMemoryRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('managed-type-raw-memory', TRuleSeverity.Error,
    'FillChar, Move oder GetMem auf verwaltete Typen');
end;

procedure TManagedTypeRawMemoryRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Types: TDeclaredTypes;
  Managed: TManagedTypes;
  Index, Call, Open, Close: Integer;
  Starts, Stops: TArray<Integer>;
  Routine: string;

  // Argumente auf oberster Ebene: Start- und Endtoken.
  procedure SplitArguments;
  var
    Inner, Depth, First: Integer;
  begin
    Starts := nil;
    Stops := nil;
    Depth := 0;
    First := NextCode(Tokens, Open + 1);
    for Inner := Open + 1 to Close do
    begin
      if (Inner = Close) or ((Depth = 0) and Tokens[Inner].IsSymbol(',')) then
      begin
        if First < Inner then
        begin
          Starts := Starts + [First];
          Stops := Stops + [PreviousCode(Tokens, Inner)];
        end;
        First := NextCode(Tokens, Inner + 1);
      end
      else if Tokens[Inner].IsSymbol('(') or Tokens[Inner].IsSymbol('[') then
      begin
        Inc(Depth);
      end
      else if Tokens[Inner].IsSymbol(')') or Tokens[Inner].IsSymbol(']') then
      begin
        Dec(Depth);
      end;
    end;
  end;

  // Argument AIndex als X, @X oder X^: Name (Tokenindex) und ob dereferenziert; -1 sonst.
  function Target(AArgument: Integer; out ADeref: Boolean): Integer;
  var
    First, Last: Integer;
  begin
    Result := -1;
    ADeref := False;
    if AArgument > High(Starts) then
    begin
      Exit;
    end;
    First := Starts[AArgument];
    Last := Stops[AArgument];
    if Tokens[First].IsSymbol('@') then
    begin
      First := NextCode(Tokens, First + 1);
    end;
    if (Last > First) and Tokens[Last].IsSymbol('^') and (NextCode(Tokens, First + 1) = Last) then
    begin
      ADeref := True;
      Last := First;
    end;
    if (First = Last) and (Tokens[First].Kind = TPascalTokenKind.Identifier) then
    begin
      Result := First;
    end;
  end;

  // Typ der Daten hinter dem Argument; bei AAsPointer (GetMem, FreeMem, X^) der Zieltyp des Zeigers.
  function DataType(AName: Integer; AAsPointer: Boolean): string;
  begin
    Result := Types.DeclaredType(Tokens[AName].Text, Tokens[AName].StartPos);
    if AAsPointer then
    begin
      Result := Managed.Pointee(Result);
    end;
  end;

  function Subject(const ATypeName, AKind: string): string;
  begin
    if Managed.IsPrimitive(ATypeName) then
    begin
      Result := Format('%s ist ein verwalteter Typ', [ATypeName]);
    end
    else
    begin
      Result := Format('%s enthält %s', [ATypeName, AKind]);
    end;
  end;

  // Anweisung: davor ;, begin, then, else, do, try, finally, except oder repeat; danach ;, end oder else.
  function IsStatement: Boolean;
  var
    Before, After: Integer;
  begin
    Before := PreviousCode(Tokens, Call);
    After := NextCode(Tokens, Close + 1);
    Result := (Before >= 0) and (Tokens[Before].IsSymbol(';') or Tokens[Before].IsKeyword('begin') or
      Tokens[Before].IsKeyword('then') or Tokens[Before].IsKeyword('else') or Tokens[Before].IsKeyword('do') or
      Tokens[Before].IsKeyword('try') or Tokens[Before].IsKeyword('finally') or Tokens[Before].IsKeyword('except') or
      Tokens[Before].IsKeyword('repeat')) and (After <= High(Tokens)) and (Tokens[After].IsSymbol(';') or
      Tokens[After].IsKeyword('end') or Tokens[After].IsKeyword('else'));
  end;

  // Argument ist SizeOf(X) oder SizeOf(T) mit X bzw. T wie angegeben.
  function IsSizeOf(AArgument: Integer; const AName, ATypeName: string): Boolean;
  var
    First, Inner, Last: Integer;
  begin
    Result := False;
    if AArgument > High(Starts) then
    begin
      Exit;
    end;
    First := Starts[AArgument];
    Inner := NextCode(Tokens, NextCode(Tokens, First + 1) + 1);
    Last := Stops[AArgument];
    Result := SameText(Tokens[First].Text, 'SizeOf') and (NextCode(Tokens, Inner + 1) = Last) and
      Tokens[Last].IsSymbol(')') and (SameText(Tokens[Inner].Text, AName) or SameText(Tokens[Inner].Text, ATypeName));
  end;

  function IsZero(AArgument: Integer): Boolean;
  begin
    Result := (AArgument <= High(Starts)) and (Starts[AArgument] = Stops[AArgument]) and
      MatchText(Tokens[Starts[AArgument]].Text, ['0', '#0', '$0', '$00']);
  end;

  procedure Report(const ATypeName, AKind, AText: string; const AFixes: TArray<TRuleFix>);
  begin
    AReport.Add(RangeOf(Tokens, Call, Close), Format('%s; %s %s', [Subject(ATypeName, AKind), Routine, AText]),
      TRuleConfidence.High, AFixes);
  end;

  procedure CheckOverwrite;
  var
    Name: Integer;
    Deref: Boolean;
    TypeName, Kind: string;
    Fixes: TArray<TRuleFix>;
  begin
    Name := Target(0, Deref);
    if Name < 0 then
    begin
      Exit;
    end;
    TypeName := DataType(Name, Deref);
    Kind := Managed.Managed(TypeName, 0);
    if Kind = '' then
    begin
      Exit;
    end;
    Fixes := nil;
    // FillChar(X, SizeOf(X), 0) bzw. ZeroMemory(@X, SizeOf(X)): X := Default(T).
    if IsStatement and not Deref and IsSizeOf(1, Tokens[Name].Text, TypeName) and
      (SameText(Routine, 'ZeroMemory') or IsZero(2)) then
    begin
      Fixes := [TRuleFix.Create(Format('%s := Default(%s)', [Tokens[Name].Text, TypeName]),
        [TRuleEdit.Create(RangeOf(Tokens, Call, Close), Format('%s := Default(%s)', [Tokens[Name].Text,
        TypeName]))], True)];
    end;
    Report(TypeName, Kind, 'überschreibt die Referenzen ohne Freigabe (Leck, ggf. Zugriffsverletzung).',
      Fixes);
  end;

  procedure CheckCopy(ASource, ADestination: Integer);
  var
    Source, Destination: Integer;
    SourceDeref, DestinationDeref: Boolean;
    SourceType, DestinationType, Kind, TypeName: string;
    Fixes: TArray<TRuleFix>;
  begin
    Source := Target(ASource, SourceDeref);
    Destination := Target(ADestination, DestinationDeref);
    SourceType := '';
    DestinationType := '';
    if Source >= 0 then
    begin
      SourceType := DataType(Source, SourceDeref);
    end;
    if Destination >= 0 then
    begin
      DestinationType := DataType(Destination, DestinationDeref);
    end;
    TypeName := DestinationType;
    Kind := Managed.Managed(DestinationType, 0);
    if Kind = '' then
    begin
      TypeName := SourceType;
      Kind := Managed.Managed(SourceType, 0);
    end;
    if Kind = '' then
    begin
      Exit;
    end;
    Fixes := nil;
    // Move(A, B, SizeOf(T)) mit gleichem Typ: B := A.
    if IsStatement and (Source >= 0) and (Destination >= 0) and not SourceDeref and not DestinationDeref and
      SameText(SourceType, DestinationType) and IsSizeOf(2, Tokens[Source].Text, SourceType) then
    begin
      Fixes := [TRuleFix.Create(Format('%s := %s', [Tokens[Destination].Text, Tokens[Source].Text]),
        [TRuleEdit.Create(RangeOf(Tokens, Call, Close), Format('%s := %s', [Tokens[Destination].Text,
        Tokens[Source].Text]))], True)];
    end;
    Report(TypeName, Kind, 'kopiert die Referenzen ohne Referenzzählung (doppelte Freigabe, ' +
      'ggf. Zugriffsverletzung).', Fixes);
  end;

  procedure CheckMemory(AAllocate: Boolean);
  var
    Name: Integer;
    Deref: Boolean;
    TypeName, Kind, Replacement: string;
    Fixes: TArray<TRuleFix>;
  begin
    Name := Target(0, Deref);
    if (Name < 0) or Deref then
    begin
      Exit;
    end;
    TypeName := DataType(Name, True);
    Kind := Managed.Managed(TypeName, 0);
    if Kind = '' then
    begin
      Exit;
    end;
    Fixes := nil;
    if AAllocate then
    begin
      Replacement := Format('New(%s)', [Tokens[Name].Text]);
    end
    else
    begin
      Replacement := Format('Dispose(%s)', [Tokens[Name].Text]);
    end;
    // GetMem(P, SizeOf(T)) bzw. FreeMem(P) oder FreeMem(P, SizeOf(T)): New bzw. Dispose.
    if IsStatement and ((Length(Starts) = 1) and not AAllocate or IsSizeOf(1, '', TypeName)) then
    begin
      Fixes := [TRuleFix.Create(Replacement, [TRuleEdit.Create(RangeOf(Tokens, Call, Close), Replacement)], True)];
    end;
    if AAllocate then
    begin
      Report(TypeName, Kind, 'lässt die Referenzen uninitialisiert (Zugriffsverletzung beim ersten ' +
        'Zuweisen); New oder Initialize verwenden.', Fixes);
    end
    else
    begin
      Report(TypeName, Kind, 'gibt die Referenzen nicht frei (Leck); Dispose oder Finalize verwenden.', Fixes);
    end;
  end;

begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  Managed := TManagedTypes.Create(AContext.Tree, AContext.Text, AContext.Index);
  try
    for Index := 0 to High(Tokens) do
    begin
      if (Tokens[Index].Kind <> TPascalTokenKind.Identifier) or not MatchText(Tokens[Index].Text, ['FillChar',
        'ZeroMemory', 'FillMemory', 'Move', 'CopyMemory', 'GetMem', 'FreeMem']) then
      begin
        Continue;
      end;
      // Methoden anderer Objekte (Stream.Move) sind nicht gemeint.
      if (PreviousCode(Tokens, Index) >= 0) and Tokens[PreviousCode(Tokens, Index)].IsSymbol('.') then
      begin
        Continue;
      end;
      Open := NextCode(Tokens, Index + 1);
      if (Open > High(Tokens)) or not Tokens[Open].IsSymbol('(') then
      begin
        Continue;
      end;
      Close := Closing(Tokens, Open);
      if Close < 0 then
      begin
        Continue;
      end;
      Call := Index;
      SplitArguments;
      Routine := Tokens[Index].Text;
      if MatchText(Routine, ['FillChar', 'ZeroMemory', 'FillMemory']) then
      begin
        CheckOverwrite;
      end
      else if SameText(Routine, 'Move') then
      begin
        CheckCopy(0, 1);
      end
      else if SameText(Routine, 'CopyMemory') then
      begin
        CheckCopy(1, 0);
      end
      else
      begin
        CheckMemory(SameText(Routine, 'GetMem'));
      end;
    end;
  finally
    Managed.Free;
    Types.Free;
  end;
end;

{ TThreadvarManagedRule }

function TThreadvarManagedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('threadvar-managed', TRuleSeverity.Warning, 'threadvar mit verwaltetem Typ');
end;

procedure TThreadvarManagedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Managed: TManagedTypes;

  procedure CheckDecl(ADecl: TSyntaxNode);
  var
    TypeName, Kind, Name, Shown: string;
    Index: Integer;
  begin
    TypeName := Managed.NodeTypeText(ADecl);
    Kind := Managed.Managed(TypeName, 0);
    if Kind = '' then
    begin
      Exit;
    end;
    Shown := TypeName;
    if not Managed.IsPrimitive(TypeName) then
    begin
      Shown := Format('%s (enthält %s)', [TypeName, Kind]);
    end;
    for Name in SplitString(ADecl.Name, ',') do
    begin
      for Index := TSyntaxTree.FirstTokenOf(Tokens, ADecl.StartOffset) to High(Tokens) do
      begin
        if Tokens[Index].Offset >= ADecl.EndOffset then
        begin
          Break;
        end;
        if (Tokens[Index].Offset >= ADecl.StartOffset) and (Tokens[Index].Kind = TPascalTokenKind.Identifier) and
          SameText(Tokens[Index].Text, Trim(Name)) then
        begin
          AReport.Add(RangeOf(Tokens, Index, Index), Format('threadvar mit %s wird beim Thread-Ende nicht ' +
            'finalisiert (Leck je Thread).', [Shown]), TRuleConfidence.High);
          Break;
        end;
      end;
    end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.VarSection) and SameText(Node.Name, 'threadvar') then
        begin
          for Index := 0 to Node.ChildCount - 1 do
          begin
            if Node[Index].Kind = TSyntaxKind.VarDecl then
            begin
              CheckDecl(Node[Index]);
            end;
          end;
          Continue;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Managed := TManagedTypes.Create(AContext.Tree, AContext.Text, AContext.Index);
  try
    Visit(AContext.Tree.Root);
  finally
    Managed.Free;
  end;
end;

{ TPCharOfTemporaryRule }

const
  PCharCasts: array[0..2] of string = ('PChar', 'PWideChar', 'PAnsiChar');
  // Umwandlungen, durch die die Regel hindurchsieht: LPARAM(PChar(…)).
  PassThroughCasts: array[0..9] of string = ('LPARAM', 'WPARAM', 'NativeInt', 'NativeUInt', 'Pointer', 'Integer',
    'Cardinal', 'Int64', 'UInt64', 'IntPtr');
  StringCasts: array[0..4] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString');
  // Asynchrone Nachrichten: der Empfänger liest den Zeiger erst nach der Anweisung.
  AsyncMessages: array[0..3] of string = ('PostMessage', 'PostThreadMessage', 'SendNotifyMessage',
    'SendMessageCallback');

function TPCharOfTemporaryRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('pchar-of-temporary', TRuleSeverity.Warning,
    'PChar auf einen temporären String');
end;

procedure TPCharOfTemporaryRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Types: TDeclaredTypes;
  Tokens: TTokens;
  LineBreak: string;

  function Text(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  // Ist einer der Bausteine (über + und Klammern) ein String? Iterativ (Bericht M1): die Verkettung ist eine
  // Oder-Verknüpfung, die Reihenfolge bleibt links vor rechts.
  function IsStringValue(ANode: TSyntaxNode): Boolean;
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
  begin
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        case Node.Kind of
          TSyntaxKind.Literal:
            if (Node.Name <> '') and CharInSet(Node.Name[1], ['''', '#']) then
            begin
              Exit(True);
            end;
          TSyntaxKind.Identifier:
            if MatchText(Types.DeclaredType(Node.Name, Node.StartPos), StringCasts) then
            begin
              Exit(True);
            end;
          TSyntaxKind.Call:
            if not MatchText(Node.Name, PCharCasts) and not MatchText(Node.Name, PassThroughCasts) then
            begin
              Exit(True);
            end;
          TSyntaxKind.ParenExpr:
            if Node.ChildCount = 1 then
            begin
              Pending.Push(Node[0]);
            end;
          TSyntaxKind.BinaryExpr:
            if (Node.Name = '+') and (Node.ChildCount = 2) then
            begin
              Pending.Push(Node[1]);
              Pending.Push(Node[0]);
            end;
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  // Nur Literale: der Compiler legt den String als Konstante ab. Iterativ (Bericht M1): Und-Verknüpfung über
  // Klammern und zweistellige Ausdrücke.
  function IsConstant(ANode: TSyntaxNode): Boolean;
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
  begin
    Result := True;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        case Node.Kind of
          TSyntaxKind.Literal:
            ;
          TSyntaxKind.ParenExpr:
            if Node.ChildCount = 1 then
            begin
              Pending.Push(Node[0]);
            end
            else
            begin
              Exit(False);
            end;
          TSyntaxKind.BinaryExpr:
            if Node.ChildCount = 2 then
            begin
              Pending.Push(Node[1]);
              Pending.Push(Node[0]);
            end
            else
            begin
              Exit(False);
            end;
        else
          Exit(False);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  // Temporärer String: Verkettung mit einem String oder Ergebnis eines Funktionsaufrufs.
  function IsTemporary(ANode: TSyntaxNode): Boolean;
  var
    Node: TSyntaxNode;
  begin
    // Iterativ (Bericht M1): durch String-Umwandlungen und Klammern hindurch.
    Node := ANode;
    while True do
    begin
      if (Node.Kind = TSyntaxKind.Call) and MatchText(Node.Name, StringCasts) and (Node.ChildCount = 2) then
      begin
        Node := Node[1];
      end
      else if Node.Kind = TSyntaxKind.ParenExpr then
      begin
        if Node.ChildCount <> 1 then
        begin
          Exit(False);
        end;
        Node := Node[0];
      end
      else
      begin
        Break;
      end;
    end;
    Result := not IsConstant(Node) and (((Node.Kind = TSyntaxKind.BinaryExpr) and IsStringValue(Node)) or
      ((Node.Kind = TSyntaxKind.Call) and IsStringValue(Node)));
  end;

  // PChar(temporär) in AValue, auch hinter LPARAM(…) und ähnlichen Umwandlungen; sonst nil.
  function TemporaryPChar(AValue: TSyntaxNode): TSyntaxNode;
  var
    Value: TSyntaxNode;
  begin
    // Iterativ (Bericht M1): durch die Umwandlungen hindurch.
    Result := nil;
    Value := AValue;
    while (Value <> nil) and (Value.Kind = TSyntaxKind.Call) and (Value.ChildCount = 2) do
    begin
      if MatchText(Value.Name, PCharCasts) and IsTemporary(Value[1]) then
      begin
        Exit(Value[1]);
      end;
      if not MatchText(Value.Name, PassThroughCasts) then
      begin
        Exit;
      end;
      Value := Value[1];
    end;
  end;

  function IsLocal(ARoutine: TSyntaxNode; const AName: string): Boolean;
  var
    Index, Inner: Integer;
    Section: TSyntaxNode;
    Name: string;
  begin
    Result := False;
    if ARoutine = nil then
    begin
      Exit;
    end;
    for Index := 0 to ARoutine.ChildCount - 1 do
    begin
      Section := ARoutine[Index];
      if (Section.Kind <> TSyntaxKind.VarSection) or not SameText(Section.Name, 'var') then
      begin
        Continue;
      end;
      for Inner := 0 to Section.ChildCount - 1 do
      begin
        if Section[Inner].Kind = TSyntaxKind.VarDecl then
        begin
          for Name in SplitString(Section[Inner].Name, ',') do
          begin
            if SameText(Trim(Name), AName) then
            begin
              Exit(True);
            end;
          end;
        end;
      end;
    end;
  end;

  // Neuer Name AName + 'Text', der in der Routine noch nicht vorkommt.
  function FreshName(ARoutine: TSyntaxNode; const ABase: string): string;
  var
    Number: Integer;

    function Used(const AName: string): Boolean;
    var
      mIndex: Integer;
    begin
      // Binär zum ersten Token der Routine statt ab Dateianfang (#1323).
      mIndex := TRoutineBody.TokenAt(Tokens, ARoutine.StartOffset);
      while (mIndex <= High(Tokens)) and (Tokens[mIndex].Offset < ARoutine.EndOffset) do
      begin
        if (Tokens[mIndex].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[mIndex].Text, AName) then
        begin
          Exit(True);
        end;
        Inc(mIndex);
      end;
      Result := False;
    end;

  begin
    Result := ABase + 'Text';
    Number := 2;
    while Used(Result) do
    begin
      Result := ABase + 'Text' + IntToStr(Number);
      Inc(Number);
    end;
  end;

  procedure CheckAssign(AStatement, ARoutine, AParent: TSyntaxNode);
  var
    Expression: TSyntaxNode;
    Target, Name, Indent: string;
    Fixes: TArray<TRuleFix>;
  begin
    Expression := TemporaryPChar(AStatement[1]);
    if Expression = nil then
    begin
      Exit;
    end;
    Target := Trim(Text(AStatement[0]));
    Fixes := nil;
    // Lokale Variable direkt in einem Block: das Zwischenergebnis in eine Inline-Variable legen.
    if (AStatement[0].Kind = TSyntaxKind.Identifier) and (AParent <> nil) and (AParent.Kind = TSyntaxKind.Block) and
      IsLocal(ARoutine, Target) then
    begin
      Name := FreshName(ARoutine, Target);
      Indent := StringOfChar(' ', AStatement.StartPos.Character);
      Fixes := [TRuleFix.Create(Format('Zwischenergebnis in %s ablegen', [Name]),
        [TRuleEdit.Create(TTextRange.Create(AStatement.StartPos, AStatement.StartPos),
        Format('var %s: string := %s;', [Name, Trim(Text(Expression))]) + LineBreak + Indent),
        TRuleEdit.Create(TTextRange.Create(Expression.StartPos, Expression.EndPos), Name)])];
    end;
    AReport.Add(TTextRange.Create(Expression.StartPos, Expression.EndPos), Format('Der Ausdruck %s ist temporär; ' +
      '%s zeigt nach dieser Zeile auf freigegebenen Speicher.', [Trim(Text(Expression)), Target]),
      TRuleConfidence.High, Fixes);
  end;

  procedure CheckAsync(ACall: TSyntaxNode);
  var
    Index: Integer;
    Expression: TSyntaxNode;
  begin
    for Index := 1 to ACall.ChildCount - 1 do
    begin
      Expression := TemporaryPChar(ACall[Index]);
      if Expression <> nil then
      begin
        AReport.Add(TTextRange.Create(Expression.StartPos, Expression.EndPos), Format('Der Ausdruck %s ist ' +
          'temporär; %s liest den Zeiger erst später aus freigegebenem Speicher.', [Trim(Text(Expression)),
          ACall.Name]), TRuleConfidence.High);
      end;
    end;
  end;

  procedure Visit(ANode, ARoutine, AParent: TSyntaxNode);
  var
    Pending, RoutineStack, Parents: TStack<TSyntaxNode>;
    Node, Routine, Parent: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1); parallele Stapel führen ARoutine und AParent je Knoten mit.
    Pending := TStack<TSyntaxNode>.Create;
    RoutineStack := TStack<TSyntaxNode>.Create;
    Parents := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      RoutineStack.Push(ARoutine);
      Parents.Push(AParent);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Routine := RoutineStack.Pop;
        Parent := Parents.Pop;
        if Node.Kind = TSyntaxKind.RoutineDecl then
        begin
          Routine := Node;
        end;
        if (Node.Kind = TSyntaxKind.AssignStatement) and (Node.ChildCount = 2) then
        begin
          CheckAssign(Node, Routine, Parent);
        end
        else if (Node.Kind = TSyntaxKind.Call) and MatchText(Node.Name, AsyncMessages) then
        begin
          CheckAsync(Node);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
          RoutineStack.Push(Routine);
          Parents.Push(Node);
        end;
      end;
    finally
      Parents.Free;
      RoutineStack.Free;
      Pending.Free;
    end;
  end;

begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  LineBreak := TTextLines.LineBreakOf(AContext.Text);
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    Visit(AContext.Tree.Root, nil, nil);
  finally
    Types.Free;
  end;
end;

{ TStringListUnsortedRule }

const
  StringListClasses: array[0..1] of string = ('TStringList', 'THashedStringList');
  // Aufrufe, die eine Liste nicht weitergeben: sie bleibt in der Hand der Routine.
  NonEscapingCalls: array[0..2] of string = ('FreeAndNil', 'Assigned', 'Free');
  // Methoden, die mit Sorted := True eine Ausnahme auslösen: dann keine Korrektur mit Sorted.
  UnsortedOnlyMethods: array[0..2] of string = ('Insert', 'Move', 'Exchange');

type
  // Was die Regel über eine Liste (lokal je Routine, sonst Feld) gesammelt hat.
  TStringListFacts = record
    Creation: TSyntaxNode;
    Sorted: Boolean;
    UnsortedOnly: Boolean;
    Hits: TArray<TSyntaxNode>;
  end;

function TStringListUnsortedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('stringlist-unsorted', TRuleSeverity.Warning,
    'Find oder Duplicates auf einer unsortierten TStringList');
end;

procedure TStringListUnsortedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Keys: TArray<string>;
  Facts: TArray<TStringListFacts>;
  Routines: TArray<TSyntaxNode>;
  LineBreak: string;

  function Text(ANode: TSyntaxNode): string;
  begin
    Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;

  // Name der Liste: X oder Self.X; sonst leer.
  function BaseName(ANode: TSyntaxNode): string;
  begin
    Result := '';
    if ANode = nil then
    begin
      Exit;
    end;
    if ANode.Kind = TSyntaxKind.Identifier then
    begin
      Result := ANode.Name;
    end
    else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and
      (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, 'Self') then
    begin
      Result := ANode.Name;
    end;
  end;

  // Deklariert die Routine AName als Variable (var-Abschnitt oder Inline-Variable)?
  function DeclaresLocal(ANode: TSyntaxNode; const AName: string): Boolean;
  var
    Pending: TStack<TSyntaxNode>;
    Node, Child: TSyntaxNode;
    Index: Integer;
    Name: string;
  begin
    // Iterativ (Bericht M1); Pending hält die Knoten, deren Kinder noch zu prüfen sind.
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Child := Node[Index];
          // Eingebettete Routinen haben eigene Variablen.
          if Child.Kind = TSyntaxKind.RoutineDecl then
          begin
            Continue;
          end;
          if Child.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.InlineVar] then
          begin
            for Name in SplitString(Child.Name, ',') do
            begin
              if SameText(Trim(Name), AName) then
              begin
                Exit(True);
              end;
            end;
          end;
          Pending.Push(Child);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  // Schlüssel der Liste an ANode: Routine und Name für lokale Variablen, sonst der Feldname.
  function KeyOf(ANode: TSyntaxNode; const AName: string): string;
  var
    Index: Integer;
    Routine: TSyntaxNode;
  begin
    // Routines ist nach Start sortiert; die innerste umgebende Routine liegt hinten.
    for Index := High(Routines) downto 0 do
    begin
      Routine := Routines[Index];
      if (Routine.StartOffset <= ANode.StartOffset) and (Routine.EndOffset >= ANode.EndOffset) and
        DeclaresLocal(Routine, AName) then
      begin
        Exit(IntToStr(Routine.StartOffset) + ':' + LowerCase(AName));
      end;
    end;
    Result := 'F:' + LowerCase(AName);
  end;

  function FactIndex(const AKey: string): Integer;
  var
    Index: Integer;
  begin
    for Index := 0 to High(Keys) do
    begin
      if Keys[Index] = AKey then
      begin
        Exit(Index);
      end;
    end;
    Result := Length(Keys);
    SetLength(Keys, Result + 1);
    SetLength(Facts, Result + 1);
    Keys[Result] := AKey;
    Facts[Result].Creation := nil;
    Facts[Result].Sorted := False;
    Facts[Result].UnsortedOnly := False;
    Facts[Result].Hits := nil;
  end;

  // Index der Liste, auf die ANode (X oder Self.X) zeigt; -1 ohne Namen.
  function ListOf(ANode: TSyntaxNode): Integer;
  var
    Name: string;
  begin
    Name := BaseName(ANode);
    if Name = '' then
    begin
      Exit(-1);
    end;
    Result := FactIndex(KeyOf(ANode, Name));
  end;

  function IsFalse(ANode: TSyntaxNode): Boolean;
  begin
    Result := (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, 'False');
  end;

  // TStringList.Create(...); ASorted, wenn Create(Duplicates, Sorted, CaseSensitive) sortiert.
  function IsCreation(AValue: TSyntaxNode; out ASorted: Boolean): Boolean;
  var
    Callee: TSyntaxNode;
  begin
    ASorted := False;
    Callee := AValue;
    if (AValue <> nil) and (AValue.Kind = TSyntaxKind.Call) and (AValue.ChildCount > 0) then
    begin
      Callee := AValue[0];
    end;
    Result := (Callee <> nil) and (Callee.Kind = TSyntaxKind.MemberAccess) and SameText(Callee.Name, 'Create') and
      (Callee.ChildCount = 1) and (Callee[0].Kind = TSyntaxKind.Identifier) and
      MatchText(Callee[0].Name, StringListClasses);
    if Result and (AValue.Kind = TSyntaxKind.Call) and (AValue.ChildCount = 4) then
    begin
      ASorted := not IsFalse(AValue[2]);
    end;
  end;

  procedure NoteCreation(AStatement: TSyntaxNode; AList: Integer; AValue: TSyntaxNode);
  var
    ConstructorSorted: Boolean;
  begin
    if (AList < 0) or not IsCreation(AValue, ConstructorSorted) then
    begin
      Exit;
    end;
    if Facts[AList].Creation = nil then
    begin
      Facts[AList].Creation := AStatement;
    end;
    if ConstructorSorted then
    begin
      Facts[AList].Sorted := True;
    end;
  end;

  // Die Liste wird weitergegeben: was der Empfänger damit macht, ist unbekannt.
  procedure NoteEscape(ANode: TSyntaxNode);
  var
    List: Integer;
  begin
    List := ListOf(ANode);
    if List >= 0 then
    begin
      Facts[List].Sorted := True;
    end;
  end;

  procedure VisitAssign(AStatement: TSyntaxNode);
  var
    Target, Value: TSyntaxNode;
    List: Integer;
  begin
    Target := AStatement[0];
    Value := AStatement[1];
    NoteCreation(AStatement, ListOf(Target), Value);
    NoteEscape(Value);
    if (Target.Kind <> TSyntaxKind.MemberAccess) or (Target.ChildCount <> 1) then
    begin
      Exit;
    end;
    List := ListOf(Target[0]);
    if List < 0 then
    begin
      Exit;
    end;
    if SameText(Target.Name, 'Sorted') and not IsFalse(Value) then
    begin
      Facts[List].Sorted := True;
    end
    else if SameText(Target.Name, 'Duplicates') and (Value.Kind = TSyntaxKind.Identifier) and
      MatchText(Value.Name, ['dupIgnore', 'dupError']) then
    begin
      Facts[List].Hits := Facts[List].Hits + [AStatement];
    end;
  end;

  // X.Methode oder X.Methode(...): Sortieren, Find und Methoden, die nur unsortiert gehen.
  procedure VisitMember(AMember, ACall: TSyntaxNode);
  var
    List: Integer;
  begin
    if AMember.ChildCount <> 1 then
    begin
      Exit;
    end;
    List := ListOf(AMember[0]);
    if List < 0 then
    begin
      Exit;
    end;
    if SameText(AMember.Name, 'Sort') or SameText(AMember.Name, 'CustomSort') then
    begin
      Facts[List].Sorted := True;
    end;
    if MatchText(AMember.Name, UnsortedOnlyMethods) then
    begin
      Facts[List].UnsortedOnly := True;
    end;
    if SameText(AMember.Name, 'Find') and (ACall <> nil) and (ACall.ChildCount = 3) then
    begin
      Facts[List].Hits := Facts[List].Hits + [ACall];
    end;
  end;

  procedure VisitNode(ANode: TSyntaxNode);
  var
    Index: Integer;
    Value: TSyntaxNode;
  begin
    case ANode.Kind of
      TSyntaxKind.AssignStatement:
        if ANode.ChildCount = 2 then
        begin
          VisitAssign(ANode);
        end;
      TSyntaxKind.InlineVar:
        if (ANode.ChildCount > 0) and (Pos(',', ANode.Name) = 0) then
        begin
          Value := ANode[ANode.ChildCount - 1];
          NoteEscape(Value);
          NoteCreation(ANode, FactIndex(KeyOf(ANode, Trim(ANode.Name))), Value);
        end;
      TSyntaxKind.Call:
        begin
          if (ANode.ChildCount > 0) and (ANode[0].Kind = TSyntaxKind.MemberAccess) then
          begin
            VisitMember(ANode[0], ANode);
          end;
          // Als Argument übergeben: der Aufgerufene kann sortieren.
          if not MatchText(ANode.Name, NonEscapingCalls) then
          begin
            for Index := 1 to ANode.ChildCount - 1 do
            begin
              NoteEscape(ANode[Index]);
            end;
          end;
        end;
      TSyntaxKind.CallStatement:
        if (ANode.ChildCount = 1) and (ANode[0].Kind = TSyntaxKind.MemberAccess) then
        begin
          VisitMember(ANode[0], nil);
        end;
      TSyntaxKind.WithStatement:
        // with X do Sorted := True ist nicht nachvollziehbar: als sortiert betrachten.
        for Index := 0 to ANode.ChildCount - 2 do
        begin
          NoteEscape(ANode[Index]);
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1), Reihenfolge wie die frühere Rekursion.
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        VisitNode(Node);
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  procedure CollectRoutines(ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1), Reihenfolge wie die frühere Rekursion (nach Start sortiert).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.RoutineDecl then
        begin
          Routines := Routines + [Node];
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  function Indent(ANode: TSyntaxNode): string;
  begin
    Result := StringOfChar(' ', ANode.StartPos.Character);
  end;

  function ListName(const AFacts: TStringListFacts): string;
  begin
    if AFacts.Creation.Kind = TSyntaxKind.InlineVar then
    begin
      Result := Trim(AFacts.Creation.Name);
    end
    else
    begin
      Result := Text(AFacts.Creation[0]);
    end;
  end;

  // Sorted := True direkt nach dem Erzeugen; nur in einem Anweisungsblock.
  function SortedFix(const AFacts: TStringListFacts): TArray<TRuleFix>;
  var
    Creation: TSyntaxNode;
  begin
    Result := nil;
    Creation := AFacts.Creation;
    if AFacts.UnsortedOnly or (Creation.Parent = nil) or (Creation.Parent.Kind <> TSyntaxKind.Block) then
    begin
      Exit;
    end;
    Result := [TRuleFix.Create('Sorted := True nach dem Erzeugen ergänzen',
      [TRuleEdit.Create(TTextRange.Create(Creation.EndPos, Creation.EndPos),
      ';' + LineBreak + Indent(Creation) + ListName(AFacts) + '.Sorted := True')])];
  end;

  // if X.Find(S, I) then: vorher I := X.IndexOf(S), im if I >= 0.
  function IndexOfFix(AFind: TSyntaxNode): TArray<TRuleFix>;
  var
    Statement: TSyntaxNode;
    IndexText: string;
  begin
    Result := nil;
    Statement := AFind.Parent;
    if (Statement = nil) or (Statement.Kind <> TSyntaxKind.IfStatement) or (Statement.ChildCount = 0) or
      (Statement[0] <> AFind) or (Statement.Parent = nil) or (Statement.Parent.Kind <> TSyntaxKind.Block) then
    begin
      Exit;
    end;
    IndexText := Text(AFind[2]);
    Result := [TRuleFix.Create('IndexOf statt Find verwenden',
      [TRuleEdit.Create(TTextRange.Create(Statement.StartPos, Statement.StartPos),
      Format('%s := %s.IndexOf(%s);', [IndexText, Text(AFind[0][0]), Text(AFind[1])]) + LineBreak +
      Indent(Statement)),
      TRuleEdit.Create(TTextRange.Create(AFind.StartPos, AFind.EndPos), IndexText + ' >= 0')])];
  end;

  procedure ReportUses(const AFacts: TStringListFacts);
  var
    Use: TSyntaxNode;
    Name: string;
    Fixes: TArray<TRuleFix>;
  begin
    Name := ListName(AFacts);
    for Use in AFacts.Hits do
    begin
      if Use.Kind = TSyntaxKind.Call then
      begin
        Fixes := SortedFix(AFacts);
        Fixes := Fixes + IndexOfFix(Use);
        AReport.Add(TTextRange.Create(Use.StartPos, Use.EndPos), Format('Find setzt eine sortierte Liste voraus; ' +
          '%s ist nicht sortiert.', [Name]), TRuleConfidence.Medium, Fixes);
      end
      else
      begin
        AReport.Add(TTextRange.Create(Use.StartPos, Use.EndPos), Format('Duplicates wirkt nur bei sortierten ' +
          'Listen; %s ist nicht sortiert.', [Name]), TRuleConfidence.Medium, SortedFix(AFacts));
      end;
    end;
  end;

var
  Index: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  LineBreak := TTextLines.LineBreakOf(AContext.Text);
  Keys := nil;
  Facts := nil;
  Routines := nil;
  CollectRoutines(AContext.Tree.Root);
  Visit(AContext.Tree.Root);
  for Index := 0 to High(Facts) do
  begin
    if (Facts[Index].Creation <> nil) and not Facts[Index].Sorted then
    begin
      ReportUses(Facts[Index]);
    end;
  end;
end;

{ TWritelnInGuiAppRule }

const
  ConsoleRoutines: array[0..3] of string = ('Write', 'Writeln', 'Read', 'Readln');
  StandardFiles: array[0..2] of string = ('Output', 'ErrOutput', 'Input');
  FileTypes: array[0..2] of string = ('Text', 'TextFile', 'File');
  IntegerTypes: array[0..13] of string = ('Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt',
    'Byte', 'Word', 'ShortInt', 'SmallInt', 'LongInt', 'LongWord', 'Int32', 'UInt32');
  FloatTypes: array[0..5] of string = ('Double', 'Single', 'Extended', 'Real', 'Currency', 'TDateTime');
  // Funktionen, die einen String liefern; dazu alle *ToStr und *ToHex.
  StringFunctions: array[0..14] of string = ('Format', 'Trim', 'TrimLeft', 'TrimRight', 'UpperCase', 'LowerCase',
    'QuotedStr', 'Copy', 'StringOfChar', 'StringReplace', 'ExtractFileName', 'ExtractFilePath', 'Concat',
    'ParamStr', 'GetCurrentDir');

function TWritelnInGuiAppRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('writeln-in-gui-app', TRuleSeverity.Warning, 'Writeln in einem Programm ohne Konsole');
end;

class function TWritelnInGuiAppRule.ApplicationKind(const AConsoleTarget, AMainSource: string): TRuleApplicationKind;
var
  Tokens: TArray<TPascalToken>;
  Token: TPascalToken;
  First, ServiceManager, Forms, FormMarker, AfterFileName: Boolean;
  Directive: string;
begin
  if SameText(Trim(AConsoleTarget), 'true') then
  begin
    Exit(TRuleApplicationKind.Console);
  end;
  Result := TRuleApplicationKind.Unknown;
  Tokens := TPascalLexer.Tokenize(AMainSource);
  First := True;
  ServiceManager := False;
  Forms := False;
  FormMarker := False;
  AfterFileName := False;
  for Token in Tokens do
    case Token.Kind of
      TPascalTokenKind.Directive:
        begin
          // {$APPTYPE CONSOLE} oder (*$APPTYPE CONSOLE*), auch in {$IFDEF}: dann gilt Konsole.
          Directive := UpperCase(Token.Text);
          Directive := StringReplace(StringReplace(Directive, '(*$', '', []), '{$', '', []);
          if StartsText('APPTYPE', Trim(Directive)) and ContainsText(Directive, 'CONSOLE') then
          begin
            Exit(TRuleApplicationKind.Console);
          end;
        end;
      TPascalTokenKind.Comment:
        // Unit1 in 'Unit1.pas' {Form1}: die IDE markiert Formulare ohne Doppelpunkt, andere Designer
        // als {Name: TDataModule} (#1060).
        if AfterFileName and StartsStr('{', Token.Text) and
          ((Pos(':', Token.Text) = 0) or ContainsText(Token.Text, ': TForm')) then
        begin
          FormMarker := True;
        end;
    else
      AfterFileName := Token.Kind = TPascalTokenKind.StringLiteral;
      if (Token.Kind = TPascalTokenKind.Identifier) and SameText(Token.Text, 'SvcMgr') then
      begin
        ServiceManager := True;
      end;
      if (Token.Kind = TPascalTokenKind.Identifier) and SameText(Token.Text, 'Forms') then
      begin
        Forms := True;
      end;
      if First then
      begin
        First := False;
        if Token.IsKeyword('program') then
        begin
          Result := TRuleApplicationKind.Gui;
        end
        else if Token.IsKeyword('library') then
        begin
          Result := TRuleApplicationKind.Library_;
        end
        // package ist kein reserviertes Wort (#943).
        else if (Token.Kind = TPascalTokenKind.Identifier) and SameText(Token.Text, 'package') then
        begin
          Exit(TRuleApplicationKind.Package);
        end
        else
        begin
          Exit(TRuleApplicationKind.Unknown);
        end;
      end;
    end;
  // Ein Dienst bindet Vcl.SvcMgr ein; mit Vcl.Forms daneben startet dasselbe Programm auch mit Oberfläche.
  if (Result = TRuleApplicationKind.Gui) and ServiceManager and not Forms then
  begin
    Result := TRuleApplicationKind.Service;
  end;
  if (Result = TRuleApplicationKind.Library_) and (Forms or FormMarker) then
  begin
    Result := TRuleApplicationKind.Unknown;
  end;
end;

class function TWritelnInGuiAppRule.Replacement(const AOptions: string): string;
var
  Value: TJSONValue;
begin
  Result := DefaultReplacement;
  if Trim(AOptions) = '' then
  begin
    Exit;
  end;
  Value := TJSONObject.ParseJSONValue(AOptions);
  try
    if (Value is TJSONObject) and TJSONObject(Value).TryGetValue<string>('replacement', Result) and
      (Trim(Result) = '') then
    begin
      Result := DefaultReplacement;
    end;
  finally
    Value.Free;
  end;
  Result := Trim(Result);
end;

procedure TWritelnInGuiAppRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Types: TDeclaredTypes;
  Tokens: TTokens;
  Declared: TArray<string>;
  ReplacementText: string;
  NeedsSysUtils: Boolean;

  function Text(ANode: TSyntaxNode): string;
  begin
    Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;

  // Namen der Routinen, die die Unit selbst deklariert (letzter Teil von TKlasse.Write).
  procedure CollectDeclared(ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
    Name: string;
  begin
    // Iterativ (Bericht M1), Reihenfolge wie die frühere Rekursion.
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.RoutineHeader] then
        begin
          Name := Node.Name;
          if Pos('.', Name) > 0 then
          begin
            Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
          end;
          Declared := Declared + [Name];
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  function DeclaredTypeOf(ANode: TSyntaxNode): string;
  begin
    Result := '';
    if ANode.Kind = TSyntaxKind.Identifier then
    begin
      Result := Types.DeclaredType(ANode.Name, ANode.StartPos);
    end;
  end;

  // Die Prüfung "if IsConsole then" zeigt, dass der Aufruf gewollt ist.
  function MentionsIsConsole(ANode: TSyntaxNode): Boolean;
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.Identifier) and SameText(Node.Name, 'IsConsole') then
        begin
          Exit(True);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  function Guarded(ANode: TSyntaxNode): Boolean;
  var
    Parent: TSyntaxNode;
  begin
    Parent := ANode.Parent;
    while Parent <> nil do
    begin
      if (Parent.Kind in [TSyntaxKind.IfStatement, TSyntaxKind.WhileStatement]) and (Parent.ChildCount > 0) and
        MentionsIsConsole(Parent[0]) then
      begin
        Exit(True);
      end;
      Parent := Parent.Parent;
    end;
    Result := False;
  end;

  // Innerhalb einer Methode: Read und Write können Methoden der Klasse sein (TStream.Read).
  function InMethod(ANode: TSyntaxNode): Boolean;
  var
    Parent: TSyntaxNode;
  begin
    Parent := ANode.Parent;
    while Parent <> nil do
    begin
      if (Parent.Kind = TSyntaxKind.RoutineDecl) and (Pos('.', Parent.Name) > 0) then
      begin
        Exit(True);
      end;
      Parent := Parent.Parent;
    end;
    Result := False;
  end;

  // AsString für Knoten ohne Unterausdrücke (Literal, Bezeichner, Aufruf); '' für alle anderen.
  function LeafAsString(ANode: TSyntaxNode): string;
  var
    TypeName: string;
  begin
    Result := '';
    case ANode.Kind of
      TSyntaxKind.Literal:
        if (ANode.Name <> '') and CharInSet(ANode.Name[1], ['''', '#']) then
        begin
          Result := Text(ANode);
        end
        else
        begin
          Result := QuotedStr(Text(ANode));
        end;
      TSyntaxKind.Identifier:
        begin
          TypeName := DeclaredTypeOf(ANode);
          if MatchText(TypeName, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'ShortString', 'Char',
            'WideChar', 'AnsiChar', 'TFileName']) then
          begin
            Result := ANode.Name;
          end
          else if MatchText(TypeName, IntegerTypes) then
          begin
            Result := 'IntToStr(' + ANode.Name + ')';
            NeedsSysUtils := True;
          end
          else if MatchText(TypeName, FloatTypes) then
          begin
            Result := 'FloatToStr(' + ANode.Name + ')';
            NeedsSysUtils := True;
          end
          else if SameText(TypeName, 'Boolean') then
          begin
            Result := 'BoolToStr(' + ANode.Name + ', True)';
            NeedsSysUtils := True;
          end;
        end;
      TSyntaxKind.Call:
        if EndsText('ToStr', ANode.Name) or EndsText('ToHex', ANode.Name) or MatchText(ANode.Name, StringFunctions) then
        begin
          Result := Text(ANode);
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;

  // Argument als String-Ausdruck für die Korrektur; '' wenn der Typ nicht sicher ist.
  function AsString(ANode: TSyntaxNode): string;
  var
    Pending: TStack<TSyntaxNode>;
    Steps: TStack<Integer>;
    Values: TStack<string>;
    Node: TSyntaxNode;
    Step: Integer;
    Value: string;
  begin
    // Iterativ (Bericht M1): Verkettungen sind so tief wie lang. Steps zählt die schon ausgewerteten Kinder;
    // Values hält die Ergebnisse. Wie zuvor wertet + die rechte Seite nur aus, wenn die linke passt.
    Pending := TStack<TSyntaxNode>.Create;
    Steps := TStack<Integer>.Create;
    Values := TStack<string>.Create;
    try
      Pending.Push(ANode);
      Steps.Push(0);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Step := Steps.Pop;
        if (Node.Kind = TSyntaxKind.BinaryExpr) and (Node.Name = '+') and (Node.ChildCount = 2) then
          case Step of
            0:
              begin
                Pending.Push(Node);
                Steps.Push(1);
                Pending.Push(Node[0]);
                Steps.Push(0);
              end;
            1:
              if Values.Pop = Text(Node[0]) then
              begin
                Pending.Push(Node);
                Steps.Push(2);
                Pending.Push(Node[1]);
                Steps.Push(0);
              end
              else
              begin
                Values.Push('');
              end;
          else
            if Values.Pop = Text(Node[1]) then
            begin
              Values.Push(Text(Node));
            end
            else
            begin
              Values.Push('');
            end;
          end
        else if (Node.Kind = TSyntaxKind.ParenExpr) and (Node.ChildCount = 1) then
        begin
          if Step = 0 then
          begin
            Pending.Push(Node);
            Steps.Push(1);
            Pending.Push(Node[0]);
            Steps.Push(0);
          end
          else
          begin
            Value := Values.Pop;
            if Value <> '' then
            begin
              Values.Push('(' + Value + ')');
            end
            else
            begin
              Values.Push('');
            end;
          end;
        end
        else
        begin
          Values.Push(LeafAsString(Node));
        end;
      end;
      Result := Values.Pop;
    finally
      Values.Free;
      Steps.Free;
      Pending.Free;
    end;
  end;

  // Breitenangaben wie X:5:2 lassen sich nicht in einen String übertragen.
  function HasWidth(ACall: TSyntaxNode): Boolean;
  var
    mIndex: Integer;
  begin
    // Binär zum ersten Token des Aufrufs statt ab Dateianfang (#1323).
    mIndex := TRoutineBody.TokenAt(Tokens, ACall.StartOffset);
    while (mIndex <= High(Tokens)) and (Tokens[mIndex].Offset < ACall.EndOffset) do
    begin
      if Tokens[mIndex].IsSymbol(':') then
      begin
        Exit(True);
      end;
      Inc(mIndex);
    end;
    Result := False;
  end;

  function Fixes(ACall: TSyntaxNode; AFirst: Integer): TArray<TRuleFix>;
  var
    Index: Integer;
    Part, Expression, NewText, Name: string;
    Edits: TArray<TRuleEdit>;
    UsesEdit: TTextEdit;
    Used: TArray<string>;
  begin
    Result := nil;
    if (ACall.Kind <> TSyntaxKind.Call) or (AFirst >= ACall.ChildCount) or HasWidth(ACall) then
    begin
      Exit;
    end;
    NeedsSysUtils := False;
    Expression := '';
    for Index := AFirst to ACall.ChildCount - 1 do
    begin
      Part := AsString(ACall[Index]);
      if Part = '' then
      begin
        Exit;
      end;
      if Expression <> '' then
      begin
        Expression := Expression + ' + ';
      end;
      Expression := Expression + Part;
    end;
    if Pos('%s', ReplacementText) > 0 then
    begin
      NewText := StringReplace(ReplacementText, '%s', Expression, []);
    end
    else if SameText(ReplacementText, TWritelnInGuiAppRule.DefaultReplacement) then
    begin
      NewText := ReplacementText + '(PChar(' + Expression + '))';
    end
    else
    begin
      NewText := ReplacementText + '(' + Expression + ')';
    end;
    Edits := [TRuleEdit.Create(TTextRange.Create(ACall.StartPos, ACall.EndPos), NewText)];
    Used := TUsesClauses.UsedUnits(Tokens);
    if SameText(ReplacementText, TWritelnInGuiAppRule.DefaultReplacement) and
      not TUsesClauses.IsUsed(Used, 'Winapi.Windows', AContext.Namespaces) and
      TUsesClauses.AddUnit(Tokens, ACall.StartOffset, 'Winapi.Windows', TTextLines.LineBreakOf(AContext.Text),
      UsesEdit) then
    begin
      Edits := Edits + [UsesEdit];
    end;
    if NeedsSysUtils and not TUsesClauses.IsUsed(Used, 'System.SysUtils', AContext.Namespaces) and
      TUsesClauses.AddUnit(Tokens, ACall.StartOffset, 'System.SysUtils', TTextLines.LineBreakOf(AContext.Text),
      UsesEdit) then
    begin
      Edits := Edits + [UsesEdit];
    end;
    Name := ReplacementText;
    if Pos('(', Name) > 0 then
    begin
      Name := Trim(Copy(Name, 1, Pos('(', Name) - 1));
    end;
    Result := [TRuleFix.Create(Format('Durch %s ersetzen', [Name]), Edits)];
  end;

  procedure CheckCall(ANode, ACallee: TSyntaxNode);
  var
    Name, TypeName: string;
    First: Integer;
    Reading: Boolean;
    Found: TArray<TRuleFix>;
  begin
    Name := ACallee.Name;
    if not MatchText(Name, ConsoleRoutines) or MatchText(Name, Declared) then
    begin
      Exit;
    end;
    if (SameText(Name, 'Write') or SameText(Name, 'Read')) and InMethod(ANode) then
    begin
      Exit;
    end;
    First := 1;
    if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 1) then
    begin
      // Erstes Argument eine Datei: kein Konsolenzugriff.
      if (ANode[1].Kind = TSyntaxKind.Identifier) and MatchText(ANode[1].Name, StandardFiles) then
      begin
        First := 2;
      end
      else
      begin
        TypeName := DeclaredTypeOf(ANode[1]);
        if MatchText(TypeName, FileTypes) or StartsText('file ', TypeName) then
        begin
          Exit;
        end;
        if (ANode[1].Kind = TSyntaxKind.Identifier) and (TypeName = '') and (ANode.ChildCount > 2) then
        begin
          Exit;
        end;
      end;
    end;
    if Guarded(ANode) then
    begin
      Exit;
    end;
    Reading := SameText(Name, 'Read') or SameText(Name, 'Readln');
    if Reading then
    begin
      Found := nil;
      AReport.Add(TTextRange.Create(ACallee.StartPos, ACallee.EndPos), Format('Das Projekt hat keine Konsole; ' +
        '%s löst zur Laufzeit E/A-Fehler 104 aus.', [Text(ACallee)]), TRuleConfidence.High, Found);
    end
    else
    begin
      AReport.Add(TTextRange.Create(ACallee.StartPos, ACallee.EndPos), Format('Das Projekt hat keine Konsole; ' +
        '%s löst zur Laufzeit E/A-Fehler 105 aus.', [Text(ACallee)]), TRuleConfidence.High, Fixes(ANode, First));
    end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.Call) and (Node.ChildCount > 0) and (Node[0].Kind = TSyntaxKind.Identifier) then
        begin
          CheckCall(Node, Node[0]);
        end
        else if (Node.Kind = TSyntaxKind.CallStatement) and (Node.ChildCount = 1) and
          (Node[0].Kind = TSyntaxKind.Identifier) then
        begin
          CheckCall(Node[0], Node[0]);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

var
  Kind: TRuleApplicationKind;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Kind := AContext.Application;
  // Ohne Projekt nur die .dpr selbst: program ohne {$APPTYPE CONSOLE}.
  if Kind = TRuleApplicationKind.Unknown then
  begin
    Kind := ApplicationKind('', AContext.Text);
  end;
  // Auch ein Windows-Dienst hat keine Konsole (#1060).
  if (Kind <> TRuleApplicationKind.Gui) and (Kind <> TRuleApplicationKind.Service) then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  ReplacementText := Replacement(AContext.Options);
  Declared := nil;
  CollectDeclared(AContext.Tree.Root);
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    Visit(AContext.Tree.Root);
  finally
    Types.Free;
  end;
end;

{ TUncheckedConversionRule }

type
  /// <summary>Umwandlung mit Try-Gegenstück: Zieltypen, die als out-Parameter passen, und Meldungstext.</summary>
  TCheckedConversion = record
    Name: string;
    Types: string;
    Problem: string;
  end;

const
  CheckedConversions: array[0..8] of TCheckedConversion = (
    (Name: 'StrToInt'; Types: ',integer,longint,'; Problem: 'ist keine Zahl'),
    (Name: 'StrToInt64'; Types: ',int64,'; Problem: 'ist keine Zahl'),
    (Name: 'StrToFloat'; Types: ',double,extended,single,'; Problem: 'ist keine Zahl'),
    (Name: 'StrToCurr'; Types: ',currency,'; Problem: 'ist kein Betrag'),
    (Name: 'StrToDate'; Types: ',tdatetime,'; Problem: 'ist kein Datum'),
    (Name: 'StrToDateTime'; Types: ',tdatetime,'; Problem: 'ist kein Zeitpunkt'),
    (Name: 'StrToTime'; Types: ',tdatetime,'; Problem: 'ist keine Uhrzeit'),
    (Name: 'StrToBool'; Types: ',boolean,'; Problem: 'ist kein Wahrheitswert'),
    (Name: 'StrToUInt'; Types: ',cardinal,longword,'; Problem: 'ist keine Zahl'));
  // Hüllen, durch die die Eingabe unverändert geprüft wird: StrToInt(Trim(Edit.Text)).
  TransparentCalls: array[0..3] of string = ('Trim', 'TrimLeft', 'TrimRight', 'Copy');

function TUncheckedConversionRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('unchecked-conversion', TRuleSeverity.Hint,
    'Umwandlung einer Benutzereingabe ohne Prüfung');
end;

procedure TUncheckedConversionRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Functions, Sources: TArray<string>;
  Types: TDeclaredTypes;
  LineBreak: string;

  function Text(ANode: TSyntaxNode): string;
  begin
    Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;

  // Edit.Text, Grid.Cells[C, R], Memo.Lines[I], auch in Trim(…); nil, wenn das Argument keine Eingabe ist.
  function InputSource(ANode: TSyntaxNode): TSyntaxNode;
  var
    Node: TSyntaxNode;
  begin
    // Iterativ (Bericht M1): durch Klammern und Hüllen wie Trim(…) hindurch.
    Result := nil;
    Node := ANode;
    while Node <> nil do
    begin
      while (Node.Kind = TSyntaxKind.ParenExpr) and (Node.ChildCount = 1) do
      begin
        Node := Node[0];
      end;
      case Node.Kind of
        TSyntaxKind.MemberAccess:
          if MatchText(Node.Name, Sources) then
          begin
            Result := Node;
          end;
        TSyntaxKind.IndexAccess:
          if (Node.ChildCount > 0) and (Node[0].Kind = TSyntaxKind.MemberAccess) and MatchText(Node.Name, Sources) then
          begin
            Result := Node;
          end;
        TSyntaxKind.Call:
          if (Node.ChildCount > 1) and MatchText(Node.Name, TransparentCalls) then
          begin
            Node := Node[1];
            Continue;
          end;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
      Node := nil;
    end;
  end;

  // Im try-Teil eines try/except: die Fehleingabe wird abgefangen.
  function Caught(ANode: TSyntaxNode): Boolean;
  var
    Child, Parent: TSyntaxNode;
  begin
    Child := ANode;
    Parent := ANode.Parent;
    while (Parent <> nil) and not (Parent.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) do
    begin
      if (Parent.Kind = TSyntaxKind.TryStatement) and not (Child.Kind in [TSyntaxKind.ExceptBlock,
        TSyntaxKind.FinallyBlock]) and (Parent.FindChild(TSyntaxKind.ExceptBlock) <> nil) then
      begin
        Exit(True);
      end;
      Child := Parent;
      Parent := Parent.Parent;
    end;
    Result := False;
  end;

  function ConversionOf(const AName: string; out AConversion: TCheckedConversion): Boolean;
  var
    Conversion: TCheckedConversion;
  begin
    for Conversion in CheckedConversions do
    begin
      if SameText(Conversion.Name, AName) then
      begin
        AConversion := Conversion;
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // X := StrToInt(Edit.Text); als eigene Anweisung in einer Anweisungsliste, X eine Variable des
  // passenden Typs: if not TryStrToInt(Edit.Text, X) then raise EConvertError.Create('X ist keine Zahl').
  function Fixes(ACall, AArgument: TSyntaxNode): TArray<TRuleFix>;
  var
    Statement, Target: TSyntaxNode;
    Conversion: TCheckedConversion;
    TypeName, Indent: string;
  begin
    Result := nil;
    Statement := ACall.Parent;
    if (Statement = nil) or (Statement.Kind <> TSyntaxKind.AssignStatement) or (Statement.ChildCount <> 2) or
      (Statement[1] <> ACall) or (Statement.Parent = nil) or not (Statement.Parent.Kind in [TSyntaxKind.Block,
      TSyntaxKind.TryStatement, TSyntaxKind.FinallyBlock, TSyntaxKind.ExceptBlock, TSyntaxKind.RepeatStatement,
      TSyntaxKind.InitializationSection, TSyntaxKind.FinalizationSection]) then
    begin
      Exit;
    end;
    Target := Statement[0];
    if (Target.Kind <> TSyntaxKind.Identifier) or not ConversionOf(ACall.Name, Conversion) then
    begin
      Exit;
    end;
    TypeName := LowerCase(Types.DeclaredType(Target.Name, Target.StartPos));
    if (TypeName = '') or (Pos(',' + TypeName + ',', Conversion.Types) = 0) then
    begin
      Exit;
    end;
    Indent := StringOfChar(' ', Statement.StartPos.Character);
    Result := [TRuleFix.Create('In Try' + Conversion.Name + ' mit Fehlerzweig umschreiben',
      [TRuleEdit.Create(TTextRange.Create(Statement.StartPos, Statement.EndPos), 'if not Try' + Conversion.Name +
      '(' + Text(AArgument) + ', ' + Target.Name + ') then' + LineBreak + Indent + '  raise EConvertError.Create(''' +
      Target.Name + ' ' + Conversion.Problem + ''')')])];
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
    Source: TSyntaxNode;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.Call) and (Node.ChildCount = 2) and MatchText(Node.Name, Functions) then
        begin
          Source := InputSource(Node[1]);
          if (Source <> nil) and not Caught(Node) then
          begin
            AReport.Add(TTextRange.Create(Node.StartPos, Node.EndPos), Format('Eingabe aus %s ohne Prüfung ' +
              'umgewandelt; eine Fehleingabe löst EConvertError aus.', [Text(Source)]), TRuleConfidence.Medium,
              Fixes(Node, Node[1]));
          end;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

var
  Defaults: TArray<string>;
  Name: string;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Defaults := nil;
  for Name in DefaultFunctions do
  begin
    Defaults := Defaults + [Name];
  end;
  Functions := TRuleOptions.Strings(AContext.Options, 'functions', Defaults);
  Defaults := nil;
  for Name in DefaultSources do
  begin
    Defaults := Defaults + [Name];
  end;
  Sources := TRuleOptions.Strings(AContext.Options, 'sources', Defaults);
  LineBreak := TTextLines.LineBreakOf(AContext.Text);
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    Visit(AContext.Tree.Root);
  finally
    Types.Free;
  end;
end;

{ TDictionaryGetWithoutCheckRule }

const
  // Aufrufe, die den Schlüssel prüfen.
  DictionaryKeyChecks: array[0..1] of string = ('ContainsKey', 'TryGetValue');
  // Aufrufe, mit denen die Routine das Dictionary selbst füllt.
  DictionaryFills: array[0..2] of string = ('Add', 'AddOrSetValue', 'TryAdd');

/// <summary>Deklariert die Routine ARoutine AName lokal (Variable, Parameter)? Sonst ist es ein Feld der Klasse
/// oder global.</summary>
function DeclaredLocally(ARoutine: TSyntaxNode; const AName: string): Boolean;
var
  Pending: TStack<TSyntaxNode>;
  Node, Child: TSyntaxNode;
  Index: Integer;
  Name: string;
begin
  // Iterativ (Bericht M1); Pending hält die Knoten, deren Kinder noch zu prüfen sind.
  Result := False;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ARoutine);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Child := Node[Index];
        if Child.Kind = TSyntaxKind.RoutineDecl then
        begin
          Continue;
        end;
        if Child.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.InlineVar, TSyntaxKind.Parameter] then
        begin
          for Name in SplitString(Child.Name, ',') do
          begin
            if SameText(Trim(Name), AName) then
            begin
              Exit(True);
            end;
          end;
        end;
        Pending.Push(Child);
      end;
    end;
  finally
    Pending.Free;
  end;
end;

function TDictionaryGetWithoutCheckRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('dictionary-get-without-check', TRuleSeverity.Hint,
    'Dictionary-Zugriff ohne Prüfung des Schlüssels');
end;

procedure TDictionaryGetWithoutCheckRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Types: TDeclaredTypes;
  LineBreak: string;

  function Text(ANode: TSyntaxNode): string;
  begin
    Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;

  // Vergleichsschlüssel: Quelltext ohne Leerraum, klein.
  function Key(ANode: TSyntaxNode): string;
  var
    Index: Integer;
    Source: string;
  begin
    Source := Text(ANode);
    Result := '';
    for Index := 1 to Length(Source) do
    begin
      if not CharInSet(Source[Index], [' ', #9, #10, #13]) then
      begin
        Result := Result + Source[Index];
      end;
    end;
    Result := LowerCase(Result);
    if StartsText('self.', Result) then
    begin
      Delete(Result, 1, 5);
    end;
  end;

  // Typtext einer Typdeklaration der Datei (TPreise = TDictionary<string, Double>), sonst ''.
  function AliasOf(ANode: TSyntaxNode; const AName: string): string;
  var
    Pending: TStack<TSyntaxNode>;
    Node, Reference: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1), Vorordnung wie die frühere Rekursion: der erste passende Typ mit Verweis zählt.
    Result := '';
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.TypeDecl) and SameText(Node.Name, AName) then
        begin
          Reference := Node.FindChild(TSyntaxKind.TypeReference);
          if Reference <> nil then
          begin
            Result := Text(Reference);
          end;
          if Result <> '' then
          begin
            Exit;
          end;
          Continue;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  // Wertetyp V aus TDictionary<K, V> bzw. TObjectDictionary<K, V>; '' wenn ADict kein Dictionary ist.
  function ValueType(ADict: TSyntaxNode): string;
  var
    Name, TypeName: string;
    Open, Depth, Index, Comma: Integer;
  begin
    Result := '';
    if ADict.Kind = TSyntaxKind.Identifier then
    begin
      Name := ADict.Name;
    end
    else if (ADict.Kind = TSyntaxKind.MemberAccess) and (ADict.ChildCount = 1) and
      (ADict[0].Kind = TSyntaxKind.Identifier) and SameText(ADict[0].Name, 'Self') then
    begin
      Name := ADict.Name;
    end
    else
    begin
      Exit;
    end;
    TypeName := Types.DeclaredType(Name, ADict.StartPos);
    if (TypeName <> '') and (Pos('<', TypeName) = 0) then
    begin
      TypeName := AliasOf(AContext.Tree.Root, TypeName);
    end;
    Open := Pos('<', TypeName);
    if (Open = 0) or not MatchText(Trim(Copy(TypeName, 1, Open - 1)), ['TDictionary', 'TObjectDictionary',
      'System.Generics.Collections.TDictionary', 'System.Generics.Collections.TObjectDictionary']) then
    begin
      Exit;
    end;
    Depth := 0;
    Comma := 0;
    for Index := Open + 1 to Length(TypeName) do
    begin
      if TypeName[Index] = '<' then
      begin
        Inc(Depth);
      end
      else if TypeName[Index] = '>' then
      begin
        if Depth = 0 then
        begin
          if Comma > 0 then
          begin
            Result := Trim(Copy(TypeName, Comma + 1, Index - Comma - 1));
          end;
          Exit;
        end;
        Dec(Depth);
      end
      else if (TypeName[Index] = ',') and (Depth = 0) then
      begin
        Comma := Index;
      end;
    end;
  end;

  // Äußerste Routine: anonyme Methoden (Vergleicher, Aufgaben) sehen die Anweisungen davor.
  function Routine(ANode: TSyntaxNode): TSyntaxNode;
  var
    Parent: TSyntaxNode;
  begin
    Result := AContext.Tree.Root;
    Parent := ANode.Parent;
    while Parent <> nil do
    begin
      if Parent.Kind = TSyntaxKind.RoutineDecl then
      begin
        Result := Parent;
      end;
      Parent := Parent.Parent;
    end;
  end;

  function MentionsKeys(ANode: TSyntaxNode): Boolean;
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.MemberAccess) and SameText(Node.Name, 'Keys') then
        begin
          Exit(True);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  function MentionsAny(ANode: TSyntaxNode; const ANames: TArray<string>): Boolean;
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.Identifier) and MatchText(Node.Name, ANames) then
        begin
          Exit(True);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  // Namen, deren Wert aus Keys eines Dictionarys stammt: for K in D.Keys, Namen := D.Keys.ToArray,
  // for N in Namen, for Pair in D mit K := Pair.Key. Bis zum Fixpunkt, weil Ketten über mehrere
  // Variablen gehen.
  function KeyNames(AScope: TSyntaxNode): TArray<string>;
  var
    Names: TArray<string>;
    Changed: Boolean;

    procedure Collect(ANode: TSyntaxNode);
    var
      Pending: TStack<TSyntaxNode>;
      Node: TSyntaxNode;
      Index: Integer;
      Source: TSyntaxNode;
      Name: string;
    begin
      // Iterativ (Bericht M1), Reihenfolge wie die frühere Rekursion.
      Pending := TStack<TSyntaxNode>.Create;
      try
        Pending.Push(ANode);
        while Pending.Count > 0 do
        begin
          Node := Pending.Pop;
          Name := '';
          Source := nil;
          if (Node.Kind = TSyntaxKind.ForInStatement) and (Node.ChildCount >= 2) then
          begin
            Name := Node.Name;
            Source := Node[Node.ChildCount - 2];
          end
          else if (Node.Kind = TSyntaxKind.AssignStatement) and (Node.ChildCount = 2) and
            (Node[0].Kind = TSyntaxKind.Identifier) then
          begin
            Name := Node[0].Name;
            Source := Node[1];
          end;
          if (Source <> nil) and not MatchText(Name, Names) and (MentionsKeys(Source) or MentionsAny(Source, Names) or
            ((Node.Kind = TSyntaxKind.ForInStatement) and (ValueType(Source) <> ''))) then
          begin
            Names := Names + [Name];
            Changed := True;
          end;
          for Index := Node.ChildCount - 1 downto 0 do
          begin
            Pending.Push(Node[Index]);
          end;
        end;
      finally
        Pending.Free;
      end;
    end;

  begin
    Names := nil;
    repeat
      Changed := False;
      Collect(AScope);
    until not Changed;
    Result := Names;
  end;

  // Füllt ANode das Dictionary ADict (Add, AddOrSetValue, Dict[K] := …) oder übergibt es einer Routine, die es
  // füllen kann (ReadProperties(…, Infos), #1109)?
  function Fills(ANode, AAccess: TSyntaxNode; const ADict: string): Boolean;
  var
    Index: Integer;
  begin
    Result := False;
    if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount >= 2) and (ANode[0].Kind = TSyntaxKind.MemberAccess) and
      (ANode[0].ChildCount = 1) and (Key(ANode[0][0]) = ADict) and MatchText(ANode.Name, DictionaryFills) then
    begin
      Exit(True);
    end;
    if (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) and (ANode[0] <> AAccess) and
      (ANode[0].Kind = TSyntaxKind.IndexAccess) and (ANode[0].ChildCount = 2) and (Key(ANode[0][0]) = ADict) then
    begin
      Exit(True);
    end;
    if ANode.Kind = TSyntaxKind.Call then
    begin
      for Index := 1 to ANode.ChildCount - 1 do
      begin
        if Key(ANode[Index]) = ADict then
        begin
          Exit(True);
        end;
      end;
    end;
  end;

  // Füllt eine Schleife um AAccess ADict, auch hinter dem Zugriff? Dann füllt ein früherer Durchlauf
  // (Nachordnung mit Merktabelle: die Kinder vor dem Knoten, auch über eine innere for-Schleife, #1109).
  function FilledInLoop(AScope, AAccess: TSyntaxNode; const ADict: string): Boolean;
  var
    Loop, Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
    Index: Integer;
  begin
    Result := False;
    Loop := AAccess.Parent;
    Pending := TStack<TSyntaxNode>.Create;
    try
      while (Loop <> nil) and (Loop <> AScope) do
      begin
        if Loop.Kind in [TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement, TSyntaxKind.ForStatement,
          TSyntaxKind.ForInStatement] then
        begin
          Pending.Clear;
          Pending.Push(Loop);
          while Pending.Count > 0 do
          begin
            Node := Pending.Pop;
            if (Node.StartOffset > AAccess.EndOffset) and Fills(Node, AAccess, ADict) then
            begin
              Exit(True);
            end;
            for Index := Node.ChildCount - 1 downto 0 do
            begin
              Pending.Push(Node[Index]);
            end;
          end;
        end;
        Loop := Loop.Parent;
      end;
    finally
      Pending.Free;
    end;
  end;

  // Ein Feld (oder eine globale Variable), das die Unit an anderer Stelle füllt: Welche Schlüssel drin sind,
  // sichert die Klasse über ihre Methoden hinweg (FOrder und FPending im Gleichschritt, Tabelle je Control beim
  // Aufbau); das sieht die Prüfung einer einzelnen Routine nicht (#1109).
  function FieldFilledInUnit(AScope, AAccess, ADictNode: TSyntaxNode; const ADict: string): Boolean;
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    Result := False;
    if (ADictNode.Kind = TSyntaxKind.Identifier) and DeclaredLocally(AScope, ADictNode.Name) then
    begin
      Exit;
    end;
    if not (ADictNode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
    begin
      Exit;
    end;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(AContext.Tree.Root);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Fills(Node, AAccess, ADict) then
        begin
          Exit(True);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  // ContainsKey/TryGetValue mit demselben Schlüssel oder Add, AddOrSetValue, Dict[K] := … vor AAccess.
  function Checked(AScope, AAccess: TSyntaxNode; const ADict, AKey: string): Boolean;
  var
    Pending: TStack<TSyntaxNode>;
    Index: Integer;
    Node, Callee: TSyntaxNode;
  begin
    if FilledInLoop(AScope, AAccess, ADict) then
    begin
      Exit(True);
    end;
    // Iterativ (Bericht M1); Kinder ab dem Ende des Zugriffs bleiben wie zuvor aus.
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(AScope);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.StartOffset < AAccess.StartOffset then
        begin
          if (Node.Kind = TSyntaxKind.Call) and (Node.ChildCount >= 2) and
            (Node[0].Kind = TSyntaxKind.MemberAccess) and (Node[0].ChildCount = 1) then
          begin
            Callee := Node[0];
            if (Key(Callee[0]) = ADict) and MatchText(Node.Name, DictionaryKeyChecks) and (Key(Node[1]) = AKey) then
            begin
              Exit(True);
            end;
          end;
          if Fills(Node, AAccess, ADict) then
          begin
            Exit(True);
          end;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          if Node[Index].StartOffset < AAccess.EndOffset then
          begin
            Pending.Push(Node[Index]);
          end;
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  function DefaultValue(const AType: string): string;
  begin
    if TDeclaredTypes.IsInt32(AType) or TDeclaredTypes.IsInt64(AType) or TDeclaredTypes.IsFloat(AType) or
      SameText(AType, 'Currency') then
    begin
      Result := '0';
    end
    else if MatchText(AType, ['string', 'UnicodeString', 'AnsiString', 'WideString']) then
    begin
      Result := '''''';
    end
    else if SameText(AType, 'Boolean') then
    begin
      Result := 'False';
    end
    else
    begin
      Result := 'Default(' + AType + ')';
    end;
  end;

  // X := Dict[K]; für sich, X eine Variable vom Wertetyp: if not Dict.TryGetValue(K, X) then X := 0.
  function Fixes(AAccess, ADictNode: TSyntaxNode; const AValueType: string): TArray<TRuleFix>;
  var
    Statement, Target: TSyntaxNode;
    Indent: string;
  begin
    Result := nil;
    Statement := AAccess.Parent;
    if (Statement = nil) or (Statement.Kind <> TSyntaxKind.AssignStatement) or (Statement.ChildCount <> 2) or
      (Statement[1] <> AAccess) or (Statement.Parent = nil) or not (Statement.Parent.Kind in [TSyntaxKind.Block,
      TSyntaxKind.TryStatement, TSyntaxKind.FinallyBlock, TSyntaxKind.ExceptBlock, TSyntaxKind.RepeatStatement,
      TSyntaxKind.InitializationSection, TSyntaxKind.FinalizationSection]) then
    begin
      Exit;
    end;
    Target := Statement[0];
    if (Target.Kind <> TSyntaxKind.Identifier) or
      not SameText(Types.DeclaredType(Target.Name, Target.StartPos), AValueType) then
    begin
      Exit;
    end;
    Indent := StringOfChar(' ', Statement.StartPos.Character);
    Result := [TRuleFix.Create('In TryGetValue umschreiben', [TRuleEdit.Create(TTextRange.Create(Statement.StartPos,
      Statement.EndPos), 'if not ' + Text(ADictNode) + '.TryGetValue(' + Text(AAccess[AAccess.ChildCount - 1]) +
      ', ' + Target.Name + ') then' + LineBreak + Indent + '  ' + Target.Name + ' := ' + DefaultValue(AValueType))])];
  end;

  procedure CheckAccess(AAccess: TSyntaxNode);
  var
    DictNode, Scope: TSyntaxNode;
    Value: string;
  begin
    if AAccess.ChildCount <> 2 then
    begin
      Exit;
    end;
    DictNode := AAccess[0];
    // Dict.Items[K]
    if (DictNode.Kind = TSyntaxKind.MemberAccess) and SameText(DictNode.Name, 'Items') and (DictNode.ChildCount = 1) then
    begin
      DictNode := DictNode[0];
    end;
    // Schreiben: Dict[K] := V legt an bzw. überschreibt.
    if (AAccess.Parent <> nil) and (AAccess.Parent.Kind = TSyntaxKind.AssignStatement) and
      (AAccess.Parent[0] = AAccess) then
    begin
      Exit;
    end;
    Value := ValueType(DictNode);
    if Value = '' then
    begin
      Exit;
    end;
    Scope := Routine(AAccess);
    if Checked(Scope, AAccess, Key(DictNode), Key(AAccess[1])) or MentionsAny(AAccess[1], KeyNames(Scope)) or
      FieldFilledInUnit(Scope, AAccess, DictNode, Key(DictNode)) then
    begin
      Exit;
    end;
    AReport.Add(TTextRange.Create(AAccess.StartPos, AAccess.EndPos), 'Schlüssel wird nicht geprüft; fehlt er, löst ' +
      'der Zugriff EListError aus.', TRuleConfidence.Medium, Fixes(AAccess, DictNode, Value));
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.IndexAccess then
        begin
          CheckAccess(Node);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  LineBreak := TTextLines.LineBreakOf(AContext.Text);
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    Visit(AContext.Tree.Root);
  finally
    Types.Free;
  end;
end;

{ TDelimitedTextWithoutStrictRule }

function TDelimitedTextWithoutStrictRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('delimited-text-without-strict', TRuleSeverity.Warning,
    'DelimitedText ohne StrictDelimiter');
end;

procedure TDelimitedTextWithoutStrictRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Code: TArray<Integer>;

  function Token(APosition: Integer): TPascalToken;
  begin
    Result := Tokens[Code[APosition]];
  end;

  function IsSym(APosition: Integer; const ASymbol: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(Code)) and Token(APosition).IsSymbol(ASymbol);
  end;

  function IsName(APosition: Integer; const AName: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(Code)) and
      (Token(APosition).Kind = TPascalTokenKind.Identifier) and SameText(Token(APosition).Text, AName);
  end;

  // Liste vor ".Eigenschaft" bei APosition (X bzw. Self.X); '' bei anderen Ausdrücken.
  function ListBefore(APosition: Integer): string;
  begin
    Result := '';
    if not IsSym(APosition - 1, '.') or (APosition < 2) or
      (Token(APosition - 2).Kind <> TPascalTokenKind.Identifier) then
    begin
      Exit;
    end;
    if IsSym(APosition - 3, '.') and not IsName(APosition - 4, 'Self') then
    begin
      Exit;
    end;
    Result := Token(APosition - 2).Text;
  end;

  // Wird in [AFrom, ATo) "Liste.AProperty := …" gesetzt? AValue liefert das erste Token des Werts.
  function Assigns(AFrom, ATo: Integer; const AList, AProperty: string; out AValue: string): Boolean;
  var
    Position: Integer;
  begin
    for Position := 0 to High(Code) - 2 do
    begin
      if (Token(Position).Offset >= AFrom) and (Token(Position).Offset < ATo) and
        IsName(Position, AProperty) and IsSym(Position + 1, ':=') and SameText(ListBefore(Position), AList) then
      begin
        AValue := Token(Position + 2).Text;
        Exit(True);
      end;
    end;
    AValue := '';
    Result := False;
  end;

  // Erstes Kind von ANode, das AOffset enthält; nil ohne.
  function ChildAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
  var
    Index: Integer;
  begin
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      if (AOffset >= ANode[Index].StartOffset) and (AOffset < ANode[Index].EndOffset) then
      begin
        Exit(ANode[Index]);
      end;
    end;
    Result := nil;
  end;

  function RoutineAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
  var
    Node: TSyntaxNode;
  begin
    // Iterativ (Bericht M1): je Ebene in das Kind, das AOffset enthält.
    Result := nil;
    Node := ChildAt(ANode, AOffset);
    while Node <> nil do
    begin
      if Node.Kind = TSyntaxKind.RoutineDecl then
      begin
        Result := Node;
      end;
      Node := ChildAt(Node, AOffset);
    end;
  end;

  // Innerste Zuweisung unter ANode, die AOffset enthält.
  function StatementAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
  var
    Node: TSyntaxNode;
  begin
    // Iterativ (Bericht M1) wie RoutineAt.
    Result := nil;
    Node := ChildAt(ANode, AOffset);
    while Node <> nil do
    begin
      if Node.Kind = TSyntaxKind.AssignStatement then
      begin
        Result := Node;
      end;
      Node := ChildAt(Node, AOffset);
    end;
  end;

  procedure CheckAt(APosition: Integer);
  var
    List, Value, Prefix: string;
    Routine, Statement: TSyntaxNode;
    From, Till: Integer;
    Fixes: TArray<TRuleFix>;
  begin
    List := ListBefore(APosition);
    Routine := RoutineAt(AContext.Tree.Root, Token(APosition).Offset);
    if (List = '') or (Routine = nil) then
    begin
      Exit;
    end;
    // Lokal: die Routine; Feld: die ganze Unit (StrictDelimiter oft im Konstruktor).
    From := Routine.StartOffset;
    Till := Routine.EndOffset;
    if not DeclaredLocally(Routine, List) then
    begin
      From := 0;
      Till := MaxInt;
    end;
    // Ohne eigenen Delimiter bleibt die Regel still; StrictDelimiter := False ist bewusst.
    if not Assigns(Routine.StartOffset, Routine.EndOffset, List, 'Delimiter', Value) or
      Assigns(From, Till, List, 'StrictDelimiter', Value) then
    begin
      Exit;
    end;
    Fixes := nil;
    Statement := StatementAt(Routine, Token(APosition).Offset);
    if (Statement <> nil) and (Statement.Parent <> nil) and (Statement.Parent.Kind in [TSyntaxKind.Block,
      TSyntaxKind.TryStatement, TSyntaxKind.FinallyBlock, TSyntaxKind.ExceptBlock, TSyntaxKind.RepeatStatement]) then
    begin
      Prefix := '';
      if IsSym(APosition - 3, '.') then
      begin
        Prefix := 'Self.';
      end;
      Fixes := [TRuleFix.Create('StrictDelimiter := True; einfügen',
        [TRoutineBody.InsertBefore(AContext.Text, Statement, Prefix + List + '.StrictDelimiter := True;')])];
    end;
    AReport.Add(TTextRange.Create(Token(APosition).StartPos, Token(APosition).EndPos),
      'Ohne StrictDelimiter trennt DelimitedText auch an Leerzeichen: ''Max Muster'' wird zu zwei Einträgen.',
      Fixes);
  end;

var
  Index, Position: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'DelimitedText') then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Code := nil;
  for Index := 0 to High(Tokens) do
  begin
    if not IsTrivia(Tokens[Index]) then
    begin
      Code := Code + [Index];
    end;
  end;
  for Position := 0 to High(Code) - 1 do
  begin
    if IsName(Position, 'DelimitedText') and IsSym(Position + 1, ':=') then
    begin
      CheckAt(Position);
    end;
  end;
end;

{ TUncheckedEnumCastRule }

const
  DefaultEnumSources: array[0..3] of string = ('FieldByName', 'ReadInteger', 'AsInteger', 'StrToInt');
  // Aufrufe, die den Wert schon begrenzen: TStatus(EnsureRange(…)).
  EnumGuards: array[0..2] of string = ('EnsureRange', 'Min', 'Max');

function TUncheckedEnumCastRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('unchecked-enum-cast', TRuleSeverity.Hint,
    'Zahl ungeprüft in Aufzählung umgewandelt');
end;

class function TUncheckedEnumCastRule.Origin(const ASource: string): string;
begin
  if MatchText(ASource, ['ReadInteger', 'ReadInt64', 'ReadBinaryData']) then
  begin
    Result := 'aus der Registry bzw. INI-Datei';
  end
  else if MatchText(ASource, ['StrToInt', 'StrToInt64', 'StrToIntDef', 'StrToUInt']) then
  begin
    Result := 'aus einem Text';
  end
  else if MatchText(ASource, ['FieldByName', 'FindField', 'Fields', 'FieldValues', 'AsInteger', 'AsLargeInt',
    'AsLongWord', 'AsSmallInt', 'ParamByName']) then
  begin
    Result := 'aus der Datenbank';
  end
  else
  begin
    Result := 'von außen';
  end;
end;

procedure TUncheckedEnumCastRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Code: TArray<Integer>;
  Sources: TArray<string>;
  LineBreak: string;
  Local: TUnitIndex;

  function Token(APosition: Integer): TPascalToken;
  begin
    Result := Tokens[Code[APosition]];
  end;

  function IsSym(APosition: Integer; const ASymbol: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(Code)) and Token(APosition).IsSymbol(ASymbol);
  end;

  function IsWord(APosition: Integer): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(Code)) and
      (Token(APosition).Kind = TPascalTokenKind.Identifier);
  end;

  function TextOf(AFirst, ALast: Integer): string;
  begin
    Result := Copy(AContext.Text, Token(AFirst).Offset + 1,
      Token(ALast).Offset + Length(Token(ALast).Text) - Token(AFirst).Offset);
  end;

  function Closing(AOpen: Integer): Integer;
  var
    Depth: Integer;
  begin
    Depth := 0;
    for Result := AOpen to High(Code) do
    begin
      if Token(Result).IsSymbol('(') or Token(Result).IsSymbol('[') then
      begin
        Inc(Depth);
      end
      else if Token(Result).IsSymbol(')') or Token(Result).IsSymbol(']') then
      begin
        Dec(Depth);
        if Depth = 0 then
        begin
          Exit;
        end;
      end;
    end;
    Result := -1;
  end;

  function CodeAt(AOffset: Integer): Integer;
  var
    mHigh, mMiddle: Integer;
  begin
    // Binär statt ab Dateianfang mit einer Kopie je Token: Code steht nach Offset sortiert (#1342).
    Result := 0;
    mHigh := Length(Code);
    while Result < mHigh do
    begin
      mMiddle := (Result + mHigh) div 2;
      if Tokens[Code[mMiddle]].Offset < AOffset then
      begin
        Result := mMiddle + 1;
      end
      else
      begin
        mHigh := mMiddle;
      end;
    end;
  end;

  // Aufzählungstyp AName in AUnit: Zahl der Werte und ob sie eigene Ordinalwerte tragen.
  function EnumIn(const AUnit: TUnitIndex; const AName: string; out ACount: Integer;
    out AExplicit: Boolean): Boolean;
  var
    Symbol: TIndexSymbol;
    Signature: string;
  begin
    Result := False;
    ACount := 0;
    AExplicit := False;
    for Symbol in AUnit.Symbols do
    begin
      if (Symbol.Kind = TIndexSymbolKind.EnumType) and (Symbol.Container = '') and SameText(Symbol.Name, AName) then
      begin
        Signature := Symbol.Signature;
        AExplicit := (Pos('(', Signature) > 0) and (Pos('=', Copy(Signature, Pos('(', Signature), MaxInt)) > 0);
        Result := True;
      end;
    end;
    if not Result then
    begin
      Exit;
    end;
    for Symbol in AUnit.Symbols do
    begin
      if (Symbol.Kind = TIndexSymbolKind.EnumMember) and SameText(Symbol.Container, AName) then
      begin
        Inc(ACount);
      end;
    end;
  end;

  function EnumInfo(const AName: string; out ACount: Integer; out AExplicit: Boolean): Boolean;
  var
    Location: TSymbolLocation;
    Owner: TUnitIndex;
  begin
    if EnumIn(Local, AName, ACount, AExplicit) then
    begin
      Exit(True);
    end;
    Result := False;
    if AContext.Index = nil then
    begin
      Exit;
    end;
    for Location in AContext.Index.FindSymbols(AName) do
    begin
      if (Location.Symbol.Kind = TIndexSymbolKind.EnumType) and (Location.Symbol.Container = '') and
        AContext.Index.FindFile(Location.FileName, Owner) and EnumIn(Owner, AName, ACount, AExplicit) then
      begin
        Exit(True);
      end;
    end;
  end;

  // Erste Quelle (aus "sources") zwischen AFirst und ALast; '' ohne.
  function SourceIn(AFirst, ALast: Integer): string;
  var
    Position: Integer;
  begin
    for Position := AFirst to ALast do
    begin
      if IsWord(Position) and MatchText(Token(Position).Text, Sources) then
      begin
        Exit(Token(Position).Text);
      end;
    end;
    Result := '';
  end;

  // V := Ausdruck mit Quelle vor ACast in der Routine, ohne dass V danach noch gelesen wird (Prüfung).
  function VariableSource(ARoutine: TSyntaxNode; AVariable, ACast: Integer): string;
  var
    Position, Assigned, Ending: Integer;
  begin
    Result := '';
    Assigned := -1;
    for Position := CodeAt(ARoutine.StartOffset) to ACast - 1 do
    begin
      if IsWord(Position) and SameText(Token(Position).Text, Token(AVariable).Text) and
        not IsSym(Position - 1, '.') then
      begin
        if IsSym(Position + 1, ':=') then
        begin
          Assigned := Position;
        end
        else if Assigned >= 0 then
        begin
          // Gelesen zwischen Zuweisung und Umwandlung: als geprüft ansehen (InRange, Vergleich, case …).
          Exit('');
        end;
      end;
    end;
    if Assigned < 0 then
    begin
      Exit;
    end;
    Ending := Assigned + 2;
    while (Ending <= High(Code)) and not Token(Ending).IsSymbol(';') and not Token(Ending).IsKeyword('end') do
    begin
      Inc(Ending);
    end;
    Result := SourceIn(Assigned + 2, Ending - 1);
    if (Result <> '') and IsWord(Assigned + 2) and MatchText(Token(Assigned + 2).Text, EnumGuards) then
    begin
      Result := '';
    end;
  end;

  // Korrektur bei TStatus(Quelle) in einer eigenen Anweisung: Hilfsvariable, InRange-Prüfung mit raise davor.
  function Fixes(ARoutine: TSyntaxNode; const ATypeName: string; AFirst, ALast: Integer): TArray<TRuleFix>;
  var
    Statement: TSyntaxNode;
    Name, Indent, Prefix: string;
    Edits: TArray<TTextEdit>;
    UsesEdit: TTextEdit;
    Used: TArray<string>;
  begin
    Result := nil;
    Statement := TRoutineBody.Enclosing(ARoutine, Token(AFirst).Offset, Token(ALast).Offset);
    while (Statement <> nil) and (Statement <> ARoutine) and not TRoutineBody.IsStatement(Statement) do
    begin
      Statement := Statement.Parent;
    end;
    if (Statement = nil) or (Statement = ARoutine) or not TRoutineBody.InList(Statement) or
      (Statement.Kind in [TSyntaxKind.Block, TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement,
      TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement, TSyntaxKind.ForStatement]) then
    begin
      Exit;
    end;
    Name := TRoutineBody.UniqueName(Tokens, AContext.NewNames.Local('Wert'));
    Indent := TTextLines.IndentOf(AContext.Text, Statement.StartPos.Line);
    Edits := [TRoutineBody.AddVariable(AContext.Text, ARoutine, Name, 'Integer', AContext.Formatting),
      TRoutineBody.InsertBefore(AContext.Text, Statement, Name + ' := ' + TextOf(AFirst, ALast) + ';' +
      LineBreak + Indent + 'if not InRange(' + Name + ', Ord(Low(' + ATypeName + ')), Ord(High(' + ATypeName +
      '))) then' + LineBreak + Indent + TRoutineBody.IndentUnit(AContext.Formatting) +
      'raise EConvertError.CreateFmt(''Ungültiger Wert %d für ' + ATypeName + ''', [' + Name + ']);'),
      TTextEdit.Create(TTextRange.Create(Token(AFirst).StartPos, Token(ALast).EndPos), Name)];
    // InRange steht in System.Math.
    Used := TUsesClauses.UsedUnits(Tokens);
    if not MatchText('System.Math', Used) and not MatchText('Math', Used) then
    begin
      Prefix := 'System.';
      if (Length(Used) > 0) and not MatchText('System.SysUtils', Used) and MatchText('SysUtils', Used) then
      begin
        Prefix := '';
      end;
      if not TUsesClauses.AddUnit(Tokens, Token(AFirst).Offset, Prefix + 'Math', LineBreak, UsesEdit) then
      begin
        Exit;
      end;
      Edits := [UsesEdit] + Edits;
    end;
    Result := [TRuleFix.Create('Prüfung mit InRange davorsetzen', Edits)];
  end;

  procedure CheckCast(APosition: Integer);
  var
    Close, Count: Integer;
    Explicit: Boolean;
    TypeName, Source, Range: string;
    Routine: TSyntaxNode;
    Direct: Boolean;
  begin
    Close := Closing(APosition + 1);
    if (Close < 0) or (Close = APosition + 2) then
    begin
      Exit;
    end;
    TypeName := Token(APosition).Text;
    if not EnumInfo(TypeName, Count, Explicit) then
    begin
      Exit;
    end;
    Routine := TRoutineBody.RoutineAt(AContext.Tree, Token(APosition).Offset);
    if Routine = nil then
    begin
      Exit;
    end;
    // Direkt: TStatus(qry.FieldByName('Status').AsInteger); über eine Variable: TStatus(Wert).
    Direct := not (IsWord(APosition + 2) and MatchText(Token(APosition + 2).Text, EnumGuards));
    Source := '';
    if Direct then
    begin
      Source := SourceIn(APosition + 2, Close - 1);
    end;
    if (Source = '') and (Close = APosition + 3) and IsWord(APosition + 2) then
    begin
      Source := VariableSource(Routine, APosition + 2, APosition);
      Direct := False;
    end;
    if Source = '' then
    begin
      Exit;
    end;
    if Explicit or (Count = 0) then
    begin
      Range := Format('Ord(Low(%s))..Ord(High(%s))', [TypeName, TypeName]);
    end
    else
    begin
      Range := Format('0..%d', [Count - 1]);
    end;
    if Direct then
    begin
      AReport.Add(TTextRange.Create(Token(APosition).StartPos, Token(Close).EndPos),
        Format('Wert %s ungeprüft nach %s umgewandelt; Werte außerhalb %s ergeben keinen gültigen %s-Wert.',
        [Origin(Source), TypeName, Range, TypeName]), TRuleConfidence.Medium,
        Fixes(Routine, TypeName, APosition + 2, Close - 1));
    end
    else
    begin
      AReport.Add(TTextRange.Create(Token(APosition).StartPos, Token(Close).EndPos),
        Format('Wert %s ungeprüft nach %s umgewandelt; Werte außerhalb %s ergeben keinen gültigen %s-Wert.',
        [Origin(Source), TypeName, Range, TypeName]), TRuleConfidence.Medium);
    end;
  end;

var
  Index, Position: Integer;
  Defaults: TArray<string>;
  Name: string;
  Cache: IRuleDerivedCache;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Defaults := nil;
  for Name in DefaultEnumSources do
  begin
    Defaults := Defaults + [Name];
  end;
  Sources := TRuleOptions.Strings(AContext.Options, 'sources', Defaults);
  if Length(Sources) = 0 then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Code := nil;
  for Index := 0 to High(Tokens) do
  begin
    if not IsTrivia(Tokens[Index]) then
    begin
      Code := Code + [Index];
    end;
  end;
  LineBreak := TTextLines.LineBreakOf(AContext.Text);
  Cache := TRuleDerived.Open(AContext);
  Local := TRuleDerived.UnitIndex(Cache, AContext);
  for Position := 0 to High(Code) - 2 do
  begin
    // TName( … ) als Ausdruck: kein Punkt davor (X.TName), kein Typ in einer Deklaration.
    if IsWord(Position) and (Token(Position).Text[1] = 'T') and IsSym(Position + 1, '(') and
      not IsSym(Position - 1, '.') then
    begin
      CheckCast(Position);
    end;
  end;
end;

{ TCreateProcessReadonlyCommandLineRule }

type
  /// <summary>Warum die Befehlszeile nicht beschreibbar ist.</summary>
{$SCOPEDENUMS ON}
  TCommandLineKind = (None, Constant, Concatenation, Variable, Parameter);
{$SCOPEDENUMS OFF}

function TCreateProcessReadonlyCommandLineRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('createprocess-readonly-commandline', TRuleSeverity.Error,
    'CreateProcess mit unveränderlicher Befehlszeile');
end;

class function TCreateProcessReadonlyCommandLineRule.CommandLineIndex(const AName: string): Integer;
begin
  // CreateProcessA kopiert die Befehlszeile selbst in einen Puffer; nur die Unicode-Fassung schreibt hinein.
  if MatchText(AName, ['CreateProcess', 'CreateProcessW']) then
  begin
    Result := 1;
  end
  else if MatchText(AName, ['CreateProcessAsUser', 'CreateProcessAsUserW']) then
  begin
    Result := 2;
  end
  else
  begin
    Result := -1;
  end;
end;

procedure TCreateProcessReadonlyCommandLineRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Types: TDeclaredTypes;
  Local: TUnitIndex;
  LineBreak: string;

  function Text(ANode: TSyntaxNode): string;
  begin
    Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;

  function IsStringLiteral(ANode: TSyntaxNode): Boolean;
  begin
    Result := (ANode.Kind = TSyntaxKind.Literal) and (ANode.Name <> '') and CharInSet(ANode.Name[1], ['''', '#']);
  end;

  function IsUnicodeString(const AType: string): Boolean;
  begin
    Result := MatchText(Trim(AType), ['string', 'UnicodeString', 'System.string', 'System.UnicodeString']);
  end;

  // Konstante (auch typisierte) aus Datei oder Index; eine gleichnamige Variable der Datei verdeckt sie.
  function IsConstant(ANode: TSyntaxNode): Boolean;
  var
    Symbol: TIndexSymbol;
    Location: TSymbolLocation;
  begin
    for Symbol in Local.Symbols do
    begin
      if (Symbol.Kind = TIndexSymbolKind.Constant) and SameText(Symbol.Name, ANode.Name) then
      begin
        Exit(True);
      end;
    end;
    if Types.DeclaredType(ANode.Name, ANode.StartPos) <> '' then
    begin
      Exit(False);
    end;
    if AContext.Index <> nil then
    begin
      for Location in AContext.Index.FindSymbols(ANode.Name) do
      begin
        if Location.Symbol.Kind = TIndexSymbolKind.Constant then
        begin
          Exit(True);
        end;
      end;
    end;
    Result := False;
  end;

  // Literal oder Konstante: zeigt auf schreibgeschützten Speicher (Referenzzähler -1).
  function IsReadonly(ANode: TSyntaxNode): Boolean;
  begin
    while (ANode.Kind = TSyntaxKind.ParenExpr) and (ANode.ChildCount = 1) do
    begin
      ANode := ANode[0];
    end;
    Result := IsStringLiteral(ANode) or ((ANode.Kind = TSyntaxKind.Identifier) and IsConstant(ANode));
  end;

  procedure Operands(ANode: TSyntaxNode; var AList: TArray<TSyntaxNode>);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
  begin
    // Iterativ (Bericht M1): die Glieder der Verkettung von links nach rechts.
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.BinaryExpr) and (Node.Name = '+') and (Node.ChildCount = 2) then
        begin
          Pending.Push(Node[1]);
          Pending.Push(Node[0]);
        end
        else
        begin
          AList := AList + [Node];
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  // 'notepad.exe ' + Datei: Ist Datei leer, liefert die Verkettung das Literal selbst zurück.
  function IsLiteralConcatenation(ANode: TSyntaxNode): Boolean;
  var
    List: TArray<TSyntaxNode>;
  begin
    List := nil;
    Operands(ANode, List);
    Result := (Length(List) = 2) and (IsReadonly(List[0]) <> IsReadonly(List[1]));
  end;

  function Classify(ANode: TSyntaxNode): TCommandLineKind;
  begin
    if IsReadonly(ANode) then
    begin
      Result := TCommandLineKind.Constant;
    end
    else if (ANode.Kind = TSyntaxKind.BinaryExpr) and IsLiteralConcatenation(ANode) then
    begin
      Result := TCommandLineKind.Concatenation;
    end
    else
    begin
      Result := TCommandLineKind.None;
    end;
  end;

  // Parameter AName der Routine (Name, Modifizierer)?
  function FindParameter(ARoutine: TSyntaxNode; const AName: string): TSyntaxNode;
  var
    Header, Params: TSyntaxNode;
    Index: Integer;
    Name: string;
  begin
    Result := nil;
    Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    if Header = nil then
    begin
      Exit;
    end;
    Params := Header.FindChild(TSyntaxKind.Parameters);
    if Params = nil then
    begin
      Exit;
    end;
    for Index := 0 to Params.ChildCount - 1 do
    begin
      for Name in SplitString(Params[Index].Name, ',') do
      begin
        if SameText(Trim(Name), AName) then
        begin
          Exit(Params[Index]);
        end;
      end;
    end;
  end;

  // Letzte Zuweisung an AName vor AOffset in ANode (Baumreihenfolge) und UniqueString(AName) danach.
  procedure Assignments(ANode: TSyntaxNode; const AName: string; AOffset: Integer; var ALast: TSyntaxNode;
    var AUnique: Integer);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1), Baumreihenfolge wie die frühere Rekursion (die letzte Zuweisung zählt).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.StartOffset >= AOffset then
        begin
          Continue;
        end;
        if (Node.Kind = TSyntaxKind.AssignStatement) and (Node.ChildCount = 2) and
          (Node[0].Kind = TSyntaxKind.Identifier) and SameText(Node[0].Name, AName) then
        begin
          ALast := Node;
        end;
        if (Node.Kind = TSyntaxKind.Call) and SameText(Node.Name, 'UniqueString') and (Node.ChildCount = 2) and
          (Node[1].Kind = TSyntaxKind.Identifier) and SameText(Node[1].Name, AName) then
        begin
          AUnique := Node.StartOffset;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  function ClassifyIdentifier(ARoutine, ANode: TSyntaxNode; AOffset: Integer): TCommandLineKind;
  var
    Last: TSyntaxNode;
    Unique: Integer;
  begin
    Result := TCommandLineKind.None;
    if not IsUnicodeString(Types.DeclaredType(ANode.Name, ANode.StartPos)) then
    begin
      Exit;
    end;
    Last := nil;
    Unique := -1;
    Assignments(ARoutine, ANode.Name, AOffset, Last, Unique);
    if Last <> nil then
    begin
      if (Unique < Last.StartOffset) and (Classify(Last[1]) <> TCommandLineKind.None) then
      begin
        Result := TCommandLineKind.Variable;
      end;
    end
    else if (Unique < 0) and (FindParameter(ARoutine, ANode.Name) <> nil) then
    begin
      Result := TCommandLineKind.Parameter;
    end;
  end;

  // Anweisung in einer Anweisungsliste, vor der die Korrektur einfügen darf; nil in Schleifenbedingungen.
  function StatementOf(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := ANode.Parent;
    while (Result <> nil) and not (TRoutineBody.IsStatement(Result) and TRoutineBody.InList(Result)) do
    begin
      if Result.Kind in [TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement, TSyntaxKind.ForStatement,
        TSyntaxKind.ForInStatement, TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
      begin
        Exit(nil);
      end;
      Result := Result.Parent;
    end;
    if (Result <> nil) and (Result.Kind in [TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement,
      TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement]) then
    begin
      Result := nil;
    end;
  end;

  function Fixes(ARoutine, AValue: TSyntaxNode; AKind: TCommandLineKind): TArray<TRuleFix>;
  var
    Statement: TSyntaxNode;
    Name, Indent: string;
  begin
    Result := nil;
    Statement := StatementOf(AValue);
    if Statement = nil then
    begin
      Exit;
    end;
    if AKind = TCommandLineKind.Variable then
    begin
      Result := [TRuleFix.Create('UniqueString(' + AValue.Name + ') davor aufrufen',
        [TRoutineBody.InsertBefore(AContext.Text, Statement, 'UniqueString(' + AValue.Name + ');')])];
      Exit;
    end;
    Name := TRoutineBody.UniqueName(AContext.Tree.Tokens, AContext.NewNames.Local('Befehl'));
    Indent := TTextLines.IndentOf(AContext.Text, Statement.StartPos.Line);
    Result := [TRuleFix.Create('Befehlszeile in eine lokale Variable kopieren und UniqueString aufrufen',
      [TRoutineBody.AddVariable(AContext.Text, ARoutine, Name, 'string', AContext.Formatting),
      TRoutineBody.InsertBefore(AContext.Text, Statement, Name + ' := ' + Text(AValue) + ';' + LineBreak + Indent +
      'UniqueString(' + Name + ');'),
      TTextEdit.Create(TTextRange.Create(AValue.StartPos, AValue.EndPos), Name)])];
  end;

  procedure CheckCall(ACall: TSyntaxNode);
  var
    Index: Integer;
    Argument, Value, Routine: TSyntaxNode;
    Kind: TCommandLineKind;
    Message: string;
    Confidence: TRuleConfidence;
  begin
    Index := CommandLineIndex(ACall.Name);
    if (Index < 0) or (ACall.ChildCount <= Index + 1) then
    begin
      Exit;
    end;
    Argument := ACall[Index + 1];
    if (Argument.Kind <> TSyntaxKind.Call) or not MatchText(Argument.Name, ['PChar', 'PWideChar']) or
      (Argument.ChildCount <> 2) then
    begin
      Exit;
    end;
    Value := Argument[1];
    Routine := TRoutineBody.RoutineAt(AContext.Tree, ACall.StartOffset);
    Kind := Classify(Value);
    if (Kind = TCommandLineKind.None) and (Value.Kind = TSyntaxKind.Identifier) and (Routine <> nil) then
    begin
      Kind := ClassifyIdentifier(Routine, Value, ACall.StartOffset);
    end;
    Confidence := TRuleConfidence.High;
    case Kind of
      TCommandLineKind.Constant:
        Message := ACall.Name + ' schreibt in die Befehlszeile; ein konstanter String ist nicht beschreibbar.';
      TCommandLineKind.Concatenation:
        Message := ACall.Name + ' schreibt in die Befehlszeile; ist der andere Teil leer, liefert die Verkettung ' +
          'das konstante Literal, das nicht beschreibbar ist.';
      TCommandLineKind.Variable:
        Message := Format('%s schreibt in die Befehlszeile; %s kann auf einen konstanten String verweisen und ist ohne ' +
          'UniqueString nicht beschreibbar.', [ACall.Name, Value.Name]);
      TCommandLineKind.Parameter:
        begin
          Message := Format('%s schreibt in die Befehlszeile; der Parameter %s kann ein konstanter String sein und ' +
            'ist ohne UniqueString nicht beschreibbar.', [ACall.Name, Value.Name]);
          Confidence := TRuleConfidence.Medium;
        end;
    else
      Exit;
    end;
    if Routine = nil then
    begin
      AReport.Add(TTextRange.Create(Value.StartPos, Value.EndPos), Message, Confidence);
    end
    else
    begin
      AReport.Add(TTextRange.Create(Value.StartPos, Value.EndPos), Message, Confidence,
        Fixes(Routine, Value, Kind));
    end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.Call then
        begin
          CheckCall(Node);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

var
  Cache: IRuleDerivedCache;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'CreateProcess') then
  begin
    Exit;
  end;
  LineBreak := TTextLines.LineBreakOf(AContext.Text);
  Cache := TRuleDerived.Open(AContext);
  Local := TRuleDerived.UnitIndex(Cache, AContext);
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    Visit(AContext.Tree.Root);
  finally
    Types.Free;
  end;
end;

{ TGlobalFormatSettingsModifiedRule }

function TGlobalFormatSettingsModifiedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('global-formatsettings-modified', TRuleSeverity.Warning,
    'Globale FormatSettings wird verändert');
end;

class function TGlobalFormatSettingsModifiedRule.Subject(const AField: string): string;
const
  // In der Reihenfolge von DeprecatedGlobals.
  Texts: array[0..19] of string = ('das Währungssymbol', 'das Währungsformat', 'das Format negativer Beträge',
    'das Tausendertrennzeichen', 'den Dezimaltrenner', 'die Nachkommastellen von Beträgen', 'das Datumstrennzeichen',
    'das kurze Datumsformat', 'das lange Datumsformat', 'das Zeittrennzeichen', 'die Vormittagskennung',
    'die Nachmittagskennung', 'das kurze Zeitformat', 'das lange Zeitformat', 'die kurzen Monatsnamen',
    'die Monatsnamen', 'die kurzen Tagesnamen', 'die Tagesnamen', 'das Listentrennzeichen',
    'das Jahrhundertfenster zweistelliger Jahreszahlen');
var
  Index: Integer;
begin
  if AField = '' then
  begin
    Exit('alle Formateinstellungen');
  end;
  for Index := 0 to High(DeprecatedGlobals) do
  begin
    if SameText(DeprecatedGlobals[Index], AField) then
    begin
      Exit(Texts[Index]);
    end;
  end;
  Result := Format('die Formateinstellung %s', [AField]);
end;

procedure TGlobalFormatSettingsModifiedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  // RTL- und VCL-Basisklassen ohne Mitglieder namens FormatSettings, DecimalSeparator …: Bricht die Kette der
  // Vorfahren ohne Index an einer von ihnen ab, ist der Name trotzdem sicher die globale Variable.
  SafeBases: array[0..18] of string = ('TObject', 'TInterfacedObject', 'TAggregatedObject', 'TContainedObject',
    'TPersistent', 'TInterfacedPersistent', 'TComponent', 'TThread', 'TCustomAttribute', 'TControl', 'TWinControl',
    'TCustomControl', 'TGraphicControl', 'TScrollingWinControl', 'TCustomForm', 'TForm', 'TCustomFrame', 'TFrame',
    'TDataModule');
type
  TModification = record
    Statement: TSyntaxNode;
    Target: TSyntaxNode;
    Routine: TSyntaxNode;
    /// <summary>Feld hinter FormatSettings bzw. die veraltete Variable; '' = die ganze FormatSettings.</summary>
    Field: string;
  end;
var
  Tokens: TTokens;
  Resolver: TNameResolver;
  mCache: IRuleDerivedCache;
  FileName, LineBreak: string;
  Used, Lines: TArray<string>;
  Found: TArray<TModification>;
  Item: TModification;
  Index, Count: Integer;
  Fixes: TArray<TRuleFix>;
  Fix: TRuleFix;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  function ChainOf(ANode: TSyntaxNode; out ANames: TArray<string>): Boolean;
  var
    Node: TSyntaxNode;
    Members: TArray<string>;
    Index: Integer;
  begin
    // Iterativ (Bericht M1): am Empfänger entlang nach innen, die Namen dann von innen nach außen.
    ANames := nil;
    Members := nil;
    Node := ANode;
    while (Node.Kind = TSyntaxKind.MemberAccess) and (Node.ChildCount > 0) do
    begin
      Members := Members + [Node.Name];
      Node := Node[0];
    end;
    Result := Node.Kind = TSyntaxKind.Identifier;
    if not Result then
    begin
      Exit;
    end;
    ANames := [Node.Name];
    for Index := High(Members) downto 0 do
    begin
      ANames := ANames + [Members[Index]];
    end;
  end;

  function InWith(ANode: TSyntaxNode): Boolean;
  begin
    Result := False;
    while (ANode <> nil) and (ANode.Kind <> TSyntaxKind.RoutineDecl) do
    begin
      if ANode.Kind = TSyntaxKind.WithStatement then
      begin
        Exit(True);
      end;
      ANode := ANode.Parent;
    end;
  end;

  /// <summary>Kann ein Vorfahr der Klasse, in deren Methode AOffset liegt, den Namen selbst deklarieren? Ja, wenn
  /// die Kette an einem unbekannten Vorfahren abbricht, der nicht in SafeBases steht.</summary>
  function UnknownAncestor(AOffset: Integer): Boolean;
  var
    Current, Next: TResolvedSymbol;
    Expected: string;
    Depth: Integer;
  begin
    Result := False;
    Current := Resolver.ResolveChain(AContext.Tree, FileName, ['Self'], AOffset);
    if Current.Kind <> TResolvedKind.Symbol then
    begin
      Exit;
    end;
    for Depth := 1 to 64 do
    begin
      if Resolver.AncestorOf(Current, Next) then
      begin
        Current := Next;
        Continue;
      end;
      Expected := '';
      if Length(Current.Ancestors) > 0 then
      begin
        Expected := Current.Ancestors[0];
      end
      else if (Current.SymbolKind = TIndexSymbolKind.ClassType) and not SameText(Current.Name, 'TObject') then
      begin
        Expected := 'TObject';
      end;
      if Pos('.', Expected) > 0 then
      begin
        Expected := Copy(Expected, LastDelimiter('.', Expected) + 1, MaxInt);
      end;
      Exit((Expected <> '') and not MatchText(Expected, SafeBases));
    end;
  end;

  /// <summary>Ist AName an der Stelle sicher die globale Variable aus System.SysUtils?</summary>
  function IsGlobal(AStatement: TSyntaxNode; const AName: string; AQualified: Boolean): Boolean;
  var
    Resolved: TResolvedSymbol;
  begin
    if AQualified then
    begin
      Exit(True);
    end;
    Result := False;
    if InWith(AStatement) or not (MatchText('System.SysUtils', Used) or MatchText('SysUtils', Used)) then
    begin
      Exit;
    end;
    Resolved := Resolver.ResolveChain(AContext.Tree, FileName, [AName], AStatement.StartOffset);
    case Resolved.Kind of
      TResolvedKind.Local, TResolvedKind.UnitName:
        Exit;
      TResolvedKind.Symbol:
        if not MatchText(Resolved.UnitName, ['System.SysUtils', 'SysUtils']) then
        begin
          Exit;
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
    Result := not UnknownAncestor(AStatement.StartOffset);
  end;

  procedure Inspect(AStatement: TSyntaxNode);
  var
    Target: TSyntaxNode;
    Names: TArray<string>;
    First: Integer;
    Modification: TModification;
  begin
    Target := AStatement[0];
    while (Target.Kind = TSyntaxKind.IndexAccess) and (Target.ChildCount > 0) do
    begin
      Target := Target[0];
    end;
    if not ChainOf(Target, Names) then
    begin
      Exit;
    end;
    First := 0;
    if (Length(Names) >= 3) and SameText(Names[0], 'System') and SameText(Names[1], 'SysUtils') then
    begin
      First := 2;
    end
    else if (Length(Names) >= 2) and SameText(Names[0], 'SysUtils') then
    begin
      First := 1;
    end;
    Modification.Field := '';
    if SameText(Names[First], 'FormatSettings') and (Length(Names) - First <= 2) then
    begin
      if Length(Names) - First = 2 then
      begin
        Modification.Field := Names[First + 1];
      end;
    end
    else if (Length(Names) - First = 1) and MatchText(Names[First], DeprecatedGlobals) then
    begin
      Modification.Field := Names[First];
    end
    else
    begin
      Exit;
    end;
    if not IsGlobal(AStatement, Names[First], First > 0) then
    begin
      Exit;
    end;
    Modification.Statement := AStatement;
    Modification.Target := AStatement[0];
    Modification.Routine := TRoutineBody.RoutineAt(AContext.Tree, AStatement.StartOffset);
    Found := Found + [Modification];
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Child: Integer;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.AssignStatement) and (Node.ChildCount >= 2) then
        begin
          Inspect(Node);
        end;
        for Child := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Child]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  /// <summary>Lokale TFormatSettings anlegen, statt der Zuweisung belegen und an die Formatierungsaufrufe danach
  /// übergeben. Nur bei einer einzeiligen Anweisung in einer Anweisungsliste mit mindestens einem solchen Aufruf.
  /// </summary>
  function LocalFix(const AItem: TModification; out AFix: TRuleFix): Boolean;
  var
    Body: TSyntaxNode;
    Name, Value, Tail, NewText: string;
    Edits: TArray<TRuleEdit>;
    Position, Close, Field: Integer;
  begin
    Result := False;
    Body := TRoutineBody.BodyOf(AItem.Routine);
    if (Body = nil) or not TRoutineBody.InList(AItem.Statement) or
      (AItem.Statement.StartPos.Line <> AItem.Statement.EndPos.Line) or
      (AItem.Statement.StartPos.Line > High(Lines)) then
    begin
      Exit;
    end;
    Name := TRoutineBody.UniqueName(Tokens, AContext.NewNames.Local('FS'));
    Edits := nil;
    Position := TRoutineBody.TokenAt(Tokens, AItem.Statement.EndOffset);
    while (Position <= High(Tokens)) and (Tokens[Position].Offset < Body.EndOffset) do
    begin
      if IsLocaleCall(Tokens, Position, Close) then
      begin
        Edits := Edits + [TRuleEdit.Create(TTextRange.Create(Tokens[Close].StartPos, Tokens[Close].StartPos),
          ', ' + Name)];
      end;
      Inc(Position);
    end;
    if Edits = nil then
    begin
      Exit;
    end;
    Value := NodeText(AItem.Statement[1]);
    if AItem.Field = '' then
    begin
      NewText := Name + ' := ' + Value;
    end
    else if SameText(AItem.Field, 'DecimalSeparator') and (Value = '''.''') then
    begin
      NewText := Name + ' := TFormatSettings.Invariant';
    end
    else
    begin
      // Feld samt Index wie geschrieben: ShortMonthNames[1] aus FormatSettings.ShortMonthNames[1].
      Field := TRoutineBody.TokenAt(Tokens, AItem.Target.StartOffset);
      while (Field <= High(Tokens)) and (Tokens[Field].Offset < AItem.Target.EndOffset) and
        not ((Tokens[Field].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Field].Text, AItem.Field)) do
      begin
        Inc(Field);
      end;
      if (Field > High(Tokens)) or (Tokens[Field].Offset >= AItem.Target.EndOffset) then
      begin
        Exit;
      end;
      Tail := Copy(AContext.Text, Tokens[Field].Offset + 1, AItem.Target.EndOffset - Tokens[Field].Offset);
      NewText := Name + ' := FormatSettings;' + LineBreak + TTextLines.IndentOf(Lines[AItem.Statement.StartPos.Line]) +
        Name + '.' + Tail + ' := ' + Value;
    end;
    Edits := [TRoutineBody.AddVariable(AContext.Text, AItem.Routine, Name, 'TFormatSettings', AContext.Formatting),
      TRuleEdit.Create(TTextRange.Create(AItem.Statement.StartPos, AItem.Statement.EndPos), NewText)] + Edits;
    AFix := TRuleFix.Create('Lokale TFormatSettings anlegen und übergeben', Edits);
    Result := True;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  if (AContext.Tree.Root.Kind in [TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile]) and
    TRuleOptions.Bool(AContext.Options, 'allowInProgram', False) then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Used := TUsesClauses.UsedUnits(Tokens);
  FileName := AContext.FileName;
  if FileName = '' then
  begin
    FileName := AContext.RelativePath;
  end;
  if FileName = '' then
  begin
    FileName := AContext.UnitName + '.pas';
  end;
  Lines := TTextLines.SplitLines(AContext.Text);
  LineBreak := TTextLines.LineBreakOf(AContext.Text);
  Found := nil;
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  Resolver := TRuleDerived.Resolver(mCache, AContext);
  Visit(AContext.Tree.Root);
  for Item in Found do
  begin
    // Die Korrektur nur bei genau einer Änderung in der Routine; sonst stellt sie etwa ein Zurücksetzen im
    // finally nicht sinnvoll um.
    Count := 0;
    for Index := 0 to High(Found) do
    begin
      if Found[Index].Routine = Item.Routine then
      begin
        Inc(Count);
      end;
    end;
    Fixes := nil;
    if (Item.Routine <> nil) and (Count = 1) and LocalFix(Item, Fix) then
    begin
      Fixes := [Fix];
    end;
    AReport.Add(TTextRange.Create(Item.Statement.StartPos, Item.Statement.EndPos),
      Format('Ändert %s für die ganze Anwendung und alle Threads; eine lokale TFormatSettings verwenden.',
      [Subject(Item.Field)]), TRuleConfidence.High, Fixes);
  end;
end;

procedure RegisterRtlTypePatternRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TInt32MulOverflowRule.Create);
  ARegistry.Register(TDelimitedTextWithoutStrictRule.Create);
  ARegistry.Register(TSizeOfPointerRule.Create);
  ARegistry.Register(TCharToPCharRule.Create);
  ARegistry.Register(TFloatEqualityRule.Create);
  ARegistry.Register(TConstructorOnInstanceRule.Create);
  ARegistry.Register(TFormatWithoutSettingsRule.Create);
  ARegistry.Register(TManagedTypeRawMemoryRule.Create);
  ARegistry.Register(TThreadvarManagedRule.Create);
  ARegistry.Register(TPCharOfTemporaryRule.Create);
  ARegistry.Register(TStringListUnsortedRule.Create);
  ARegistry.Register(TWritelnInGuiAppRule.Create);
  ARegistry.Register(TUncheckedConversionRule.Create);
  ARegistry.Register(TDictionaryGetWithoutCheckRule.Create);
  ARegistry.Register(TUncheckedEnumCastRule.Create);
  ARegistry.Register(TCreateProcessReadonlyCommandLineRule.Create);
  ARegistry.Register(TGlobalFormatSettingsModifiedRule.Create);
end;

end.
