unit BDLsp.Common.Lsp.FormSymbols;

// Hover und Gehe zu Definition in Formulardateien (#308):
//   - Property-Name (auch Font.Style und in Collection-Einträgen): Deklaration,
//     Typ, default und deklarierende Klasse; Sprung zur Property
//   - Klassenname (object btnOk: TButton): Klasse mit published-Mitgliedern; Sprung zur Klasse
//   - Aufzählungs- und Mengenwerte (alClient, [fsBold]): Typ und alle Werte; Sprung zum Wert
//   - Ereignis-Handler (OnClick = btnOkClick): Signatur der Methode aus der Unit
// Dazu die Suche nach gespeicherten Werten, die dem default entsprechen
// (Grundlage der Regel dfm-redundant-default) und die Eigenschaftsregeln aus
// dfmPropertyRules (#309, Regel dfm-property). Was sich nicht auflösen lässt
// (Klassen ohne Quellen), ergibt keinen Hover, kein Ziel und keine Meldung.

interface

uses
  System.SysUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Index.Contract,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Dfm.Contract,
  BDLsp.Common.Lsp.PublishedMembers;

type
  /// <summary>Wert in der Formulardatei, der dem default der Property entspricht.</summary>
  TRedundantDefault = record
    /// <summary>Ganze Zeile "Name = Wert".</summary>
    Range: TTextRange;
    PropertyName: string;
    Value: string;
  end;

  /// <summary>Verstoß gegen eine Eigenschaftsregel (#309).</summary>
  TFormPropertyViolation = record
    /// <summary>Gespeicherte Property-Zeile, sonst der Kopf des Objekts.</summary>
    Range: TTextRange;
    Message: string;
    /// <summary>Position der Regel in dfmPropertyRules.</summary>
    RuleIndex: Integer;
    Severity: TRuleSeverity;
    HasFix: Boolean;
    /// <summary>Korrektur gilt als sicher (fix: auto) und läuft mit source.fixAll.</summary>
    Safe: Boolean;
    Fix: TRuleEdit;
  end;

  /// <summary>Regel, deren Klasse oder Property sich nicht auflösen lässt.</summary>
  TFormPropertyRuleProblem = record
    RuleIndex: Integer;
    Message: string;
  end;

  TFormSymbols = class
  public
    /// <summary>Markdown für APosition; '' ohne Treffer. AFormFile dient dem Weg zur Unit (Ereignisse).</summary>
    class function Hover(const AText, AFormFile: string; const APosition: TTextPosition; const AIndex: ISymbolIndex;
      const AReadText: TMemberReadText): string; static;
    /// <summary>Sprungziele für Property-Namen, Klassennamen und Aufzählungswerte.</summary>
    class function Targets(const AText: string; const APosition: TTextPosition; const AIndex: ISymbolIndex;
      const AReadText: TMemberReadText): TArray<TSymbolLocation>; static;
    /// <summary>Gespeicherte Werte, die dem default der Property entsprechen.</summary>
    class function RedundantDefaults(const AText: string; const AIndex: ISymbolIndex;
      const AReadText: TMemberReadText): TArray<TRedundantDefault>; static;
    /// <summary>Verstöße gegen ARules in der Formulardatei AFileName (für exclude).</summary>
    class function PropertyViolations(const AText, AFileName: string; const ARules: TArray<TDfmPropertyRule>;
      const AIndex: ISymbolIndex; const AReadText: TMemberReadText): TArray<TFormPropertyViolation>; static;
    /// <summary>Regeln mit unbekannter Klasse oder Property.</summary>
    class function RuleProblems(const ARules: TArray<TDfmPropertyRule>; const AIndex: ISymbolIndex;
      const AReadText: TMemberReadText): TArray<TFormPropertyRuleProblem>; static;
  end;

implementation

uses
  System.StrUtils,
  BDLsp.Common.Dfm.FormFiles,
  BDLsp.Common.Dfm.Parser,
  BDLsp.Common.Dfm.Navigation,
  BDLsp.Common.Index.Extractor;

const
  MaxDepth = 32;

function Contains(const ARange: TTextRange; const APosition: TTextPosition): Boolean;
begin
  Result := ((APosition.Line > ARange.StartPos.Line) or ((APosition.Line = ARange.StartPos.Line) and
    (APosition.Character >= ARange.StartPos.Character))) and ((APosition.Line < ARange.EndPos.Line) or
    ((APosition.Line = ARange.EndPos.Line) and (APosition.Character <= ARange.EndPos.Character)));
end;

/// <summary>Klasse ohne Unit-Präfix.</summary>
function FindClassSymbol(const AIndex: ISymbolIndex; const AName: string; out ALocation: TSymbolLocation): Boolean;
var
  Location: TSymbolLocation;
  Name: string;
begin
  Name := AName;
  if LastDelimiter('.', Name) > 0 then
    Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
  if AIndex <> nil then
    for Location in AIndex.FindSymbols(Name) do
      if (Location.Symbol.Kind = TIndexSymbolKind.ClassType) and (Location.Symbol.Container = '') then
      begin
        ALocation := Location;
        Exit(True);
      end;
  Result := False;
end;

/// <summary>Published-Property AName (auch Font.Style) ab Klasse AClassName.</summary>
function ResolveProperty(const AIndex: ISymbolIndex; const AReadText: TMemberReadText; const AClassName,
  AName: string; out AMember: TPublishedMember): Boolean;
var
  Parts: TArray<string>;
  ClassName: string;
  Index: Integer;
  Member: TPublishedMember;
  Found: Boolean;
begin
  Result := False;
  if AIndex = nil then
    Exit;
  Parts := AName.Split(['.']);
  ClassName := AClassName;
  for Index := 0 to High(Parts) do
  begin
    Found := False;
    for Member in TPublishedMembers.Collect(AIndex, ClassName, AReadText) do
      if SameText(Member.Name, Parts[Index]) then
      begin
        AMember := Member;
        Found := True;
        Break;
      end;
    if not Found then
      Exit;
    ClassName := AMember.TypeName;
  end;
  Result := True;
end;

/// <summary>Klasse der Einträge einer Collection: Typ der Default-Property bzw. von Items.</summary>
function ItemClassOf(const AIndex: ISymbolIndex; const ACollectionType: string): string;
var
  ClassName: string;
  Location, Owner: TSymbolLocation;
  Depth: Integer;
begin
  Result := '';
  ClassName := ACollectionType;
  for Depth := 1 to MaxDepth do
  begin
    for Location in AIndex.FindSymbols('Items') do
      if (Location.Symbol.Kind = TIndexSymbolKind.Property_) and SameText(Location.Symbol.Container, ClassName) and
        (Location.Symbol.TypeName <> '') then
        Exit(Location.Symbol.TypeName);
    if not FindClassSymbol(AIndex, ClassName, Owner) or (Length(Owner.Symbol.Ancestors) = 0) then
      Exit;
    ClassName := Owner.Symbol.Ancestors[0];
  end;
end;

type
  /// <summary>Formulardatei mit Eltern der Objekte.</summary>
  TFormView = class
  private
    FDocument: TDfmDocument;
    FLines: TArray<string>;
    FLineBreak: string;
    function ParentOf(AParent, AObject: TDfmObject): TDfmObject;
  public
    constructor Create(const AText: string);
    destructor Destroy; override;
    /// <summary>Klasse des Objekts; bei Collection-Einträgen die Item-Klasse der Collection.</summary>
    function ClassOf(AObject: TDfmObject; const AIndex: ISymbolIndex; const AReadText: TMemberReadText): string;
    /// <summary>Wort (Bezeichner) an APosition und sein Bereich.</summary>
    function WordAt(const APosition: TTextPosition; out ARange: TTextRange): string;
    property Document: TDfmDocument read FDocument;
    property Lines: TArray<string> read FLines;
    property LineBreak: string read FLineBreak;
  end;

constructor TFormView.Create(const AText: string);
begin
  inherited Create;
  FDocument := TDfmParser.Parse(AText);
  FLines := StringReplace(AText, #13#10, #10, [rfReplaceAll]).Split([#10]);
  if Pos(#13#10, AText) > 0 then
    FLineBreak := #13#10
  else
    FLineBreak := #10;
end;

destructor TFormView.Destroy;
begin
  FDocument.Free;
  inherited;
end;

function TFormView.ParentOf(AParent, AObject: TDfmObject): TDfmObject;
var
  Child: TDfmObject;
begin
  Result := nil;
  for Child in AParent.Children do
  begin
    if Child = AObject then
      Exit(AParent);
    Result := ParentOf(Child, AObject);
    if Result <> nil then
      Exit;
  end;
end;

function TFormView.ClassOf(AObject: TDfmObject; const AIndex: ISymbolIndex; const AReadText: TMemberReadText): string;
var
  Parent: TDfmObject;
  Item: TDfmProperty;
  Member: TPublishedMember;
  ParentClass: string;
begin
  Result := AObject.TypeName;
  if (AObject.Kind <> TDfmObjectKind.Item) or (FDocument.Root = nil) then
    Exit;
  Result := '';
  Parent := ParentOf(FDocument.Root, AObject);
  if (Parent = nil) or (AIndex = nil) then
    Exit;
  ParentClass := ClassOf(Parent, AIndex, AReadText);
  // Die Collection-Property, in deren Wert (< … >) der Eintrag steht.
  for Item in Parent.Properties do
    if Contains(Item.ValueRange, AObject.Range.StartPos) then
    begin
      if ResolveProperty(AIndex, AReadText, ParentClass, Item.Name, Member) then
        Result := ItemClassOf(AIndex, Member.TypeName);
      Exit;
    end;
end;

function TFormView.WordAt(const APosition: TTextPosition; out ARange: TTextRange): string;
var
  Line: string;
  Start, Stop: Integer;
begin
  Result := '';
  if (APosition.Line < 0) or (APosition.Line > High(FLines)) then
    Exit;
  Line := FLines[APosition.Line];
  Start := APosition.Character;
  while (Start > 0) and CharInSet(Line[Start], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
    Dec(Start);
  Stop := APosition.Character + 1;
  while (Stop <= Length(Line)) and CharInSet(Line[Stop], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
    Inc(Stop);
  Result := Copy(Line, Start + 1, Stop - Start - 1);
  ARange := TTextRange.Create(APosition.Line, Start, APosition.Line, Stop - 1);
end;

/// <summary>Aufzählungswert AName: Ort und Typ.</summary>
function FindEnumMember(const AIndex: ISymbolIndex; const AName: string; out ALocation: TSymbolLocation): Boolean;
var
  Location: TSymbolLocation;
begin
  if (AIndex <> nil) and IsValidIdent(AName) then
    for Location in AIndex.FindSymbols(AName) do
      if Location.Symbol.Kind = TIndexSymbolKind.EnumMember then
      begin
        ALocation := Location;
        Exit(True);
      end;
  Result := False;
end;

function EnumValues(const AIndex: ISymbolIndex; const ALocation: TSymbolLocation): string;
var
  UnitIndex: TUnitIndex;
  Symbol: TIndexSymbol;
begin
  Result := '';
  if not AIndex.FindFile(ALocation.FileName, UnitIndex) then
    Exit;
  for Symbol in UnitIndex.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.EnumMember) and SameText(Symbol.Container, ALocation.Symbol.Container) then
    begin
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + Symbol.Name;
    end;
end;

function PropertyMarkdown(const AMember: TPublishedMember): string;
var
  Declaration: string;
begin
  Declaration := 'property ' + AMember.Name;
  if AMember.TypeName <> '' then
    Declaration := Declaration + ': ' + AMember.TypeName;
  if AMember.DefaultValue <> '' then
    Declaration := Declaration + ' default ' + AMember.DefaultValue;
  Result := '```pascal' + sLineBreak + Declaration + sLineBreak + '```';
  if AMember.TypeClass <> '' then
    Result := Result + sLineBreak + sLineBreak + 'Deklariert in `' + AMember.TypeClass + '`'
  else
    Result := Result + sLineBreak + sLineBreak + 'Deklariert in `' + AMember.DeclaringClass + '`';
end;

/// <summary>Kopf der Methode AName der Klasse AFormClass in der Unit neben AFormFile.</summary>
function HandlerSignature(const AFormFile, AFormClass, AName: string; const AReadText: TMemberReadText): string;
var
  UnitFile, Text, Line: string;
  UnitIndex: TUnitIndex;
  Symbol: TIndexSymbol;
  Lines: TArray<string>;
  Index: Integer;
begin
  Result := '';
  if (AFormFile = '') or not Assigned(AReadText) then
    Exit;
  UnitFile := TFormFiles.UnitFile(AFormFile);
  if not AReadText(UnitFile, Text) then
    Exit;
  UnitIndex := TIndexExtractor.ExtractText(Text, UnitFile, nil);
  Lines := StringReplace(Text, #13#10, #10, [rfReplaceAll]).Split([#10]);
  for Symbol in UnitIndex.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.Method) and SameText(Symbol.Name, AName) and
      SameText(Symbol.Container, AFormClass) then
    begin
      // Erste Fundstelle ist die Deklaration in der Klasse.
      for Index := Symbol.Range.StartPos.Line to Symbol.Range.EndPos.Line do
      begin
        Line := Trim(Lines[Index]);
        if Result <> '' then
          Result := Result + ' ';
        Result := Result + Line;
        if Pos(';', Line) > 0 then
          Break;
      end;
      Exit('```pascal' + sLineBreak + Result + sLineBreak + '```');
    end;
end;

class function TFormSymbols.Hover(const AText, AFormFile: string; const APosition: TTextPosition;
  const AIndex: ISymbolIndex; const AReadText: TMemberReadText): string;
var
  View: TFormView;
  Current: TDfmObject;
  Item: TDfmProperty;
  Member: TPublishedMember;
  Location: TSymbolLocation;
  ClassName, Word: string;
  WordRange: TTextRange;
begin
  Result := '';
  View := TFormView.Create(AText);
  try
    if View.Document.Root = nil then
      Exit;
    Current := TDfmNavigation.ObjectAt(View.Document, APosition);
    if Current = nil then
      Exit;
    // Klassenname im Kopf des Objekts.
    if (Current.TypeName <> '') and Contains(Current.TypeRange, APosition) then
    begin
      if not FindClassSymbol(AIndex, Current.TypeName, Location) then
        Exit;
      Result := '```pascal' + sLineBreak + Location.Symbol.Name + ' = class';
      if Length(Location.Symbol.Ancestors) > 0 then
        Result := Result + '(' + string.Join(', ', Location.Symbol.Ancestors) + ')';
      Result := Result + sLineBreak + '```' + sLineBreak + sLineBreak + 'Unit `' + Location.UnitName + '`';
      Word := TPublishedMembers.ToMarkdown(TPublishedMembers.Collect(AIndex, Location.Symbol.Name, AReadText));
      if Word <> '' then
        Result := Result + sLineBreak + sLineBreak + Word;
      Exit;
    end;
    ClassName := View.ClassOf(Current, AIndex, AReadText);
    for Item in Current.Properties do
    begin
      if Contains(Item.NameRange, APosition) then
      begin
        if (ClassName <> '') and ResolveProperty(AIndex, AReadText, ClassName, Item.Name, Member) then
          Result := PropertyMarkdown(Member);
        Exit;
      end;
      if not Contains(Item.ValueRange, APosition) then
        Continue;
      if Item.IsEvent then
        Exit(HandlerSignature(AFormFile, View.Document.Root.TypeName, Item.Value, AReadText));
      Word := View.WordAt(APosition, WordRange);
      if FindEnumMember(AIndex, Word, Location) then
        Result := '```pascal' + sLineBreak + Location.Symbol.Name + ': ' + Location.Symbol.Container + sLineBreak +
          '```' + sLineBreak + sLineBreak + 'Werte: ' + EnumValues(AIndex, Location);
      Exit;
    end;
  finally
    View.Free;
  end;
end;

class function TFormSymbols.Targets(const AText: string; const APosition: TTextPosition;
  const AIndex: ISymbolIndex; const AReadText: TMemberReadText): TArray<TSymbolLocation>;
var
  View: TFormView;
  Current: TDfmObject;
  Item: TDfmProperty;
  Member: TPublishedMember;
  Location: TSymbolLocation;
  ClassName, Word, Owner: string;
  WordRange: TTextRange;
begin
  Result := nil;
  if AIndex = nil then
    Exit;
  View := TFormView.Create(AText);
  try
    if View.Document.Root = nil then
      Exit;
    Current := TDfmNavigation.ObjectAt(View.Document, APosition);
    if Current = nil then
      Exit;
    if (Current.TypeName <> '') and Contains(Current.TypeRange, APosition) then
    begin
      if FindClassSymbol(AIndex, Current.TypeName, Location) then
        Result := [Location];
      Exit;
    end;
    ClassName := View.ClassOf(Current, AIndex, AReadText);
    for Item in Current.Properties do
    begin
      if Contains(Item.NameRange, APosition) then
      begin
        if (ClassName = '') or not ResolveProperty(AIndex, AReadText, ClassName, Item.Name, Member) then
          Exit;
        Owner := Member.TypeClass;
        if Owner = '' then
          Owner := Member.DeclaringClass;
        for Location in AIndex.FindSymbols(Member.Name) do
          if (Location.Symbol.Kind = TIndexSymbolKind.Property_) and SameText(Location.Symbol.Container, Owner) then
            Exit([Location]);
        Exit;
      end;
      if Contains(Item.ValueRange, APosition) and not Item.IsEvent then
      begin
        Word := View.WordAt(APosition, WordRange);
        if FindEnumMember(AIndex, Word, Location) then
          Result := [Location];
        Exit;
      end;
    end;
  finally
    View.Free;
  end;
end;

class function TFormSymbols.RedundantDefaults(const AText: string; const AIndex: ISymbolIndex;
  const AReadText: TMemberReadText): TArray<TRedundantDefault>;
var
  View: TFormView;
  Found: TArray<TRedundantDefault>;

  procedure Visit(AObject: TDfmObject);
  var
    Item: TDfmProperty;
    Member: TPublishedMember;
    Entry: TRedundantDefault;
    ClassName: string;
    Child: TDfmObject;
  begin
    ClassName := View.ClassOf(AObject, AIndex, AReadText);
    if ClassName <> '' then
      for Item in AObject.Properties do
        if not Item.IsEvent and ResolveProperty(AIndex, AReadText, ClassName, Item.Name, Member) and
          (Member.DefaultValue <> '') and SameText(Trim(Item.Value), Member.DefaultValue) then
        begin
          Entry.Range := TTextRange.Create(Item.NameRange.StartPos, Item.ValueRange.EndPos);
          Entry.PropertyName := Item.Name;
          Entry.Value := Trim(Item.Value);
          Found := Found + [Entry];
        end;
    for Child in AObject.Children do
      Visit(Child);
  end;

begin
  Found := nil;
  if AIndex = nil then
    Exit(nil);
  View := TFormView.Create(AText);
  try
    if View.Document.Root <> nil then
      Visit(View.Document.Root);
  finally
    View.Free;
  end;
  Result := Found;
end;


{ Eigenschaftsregeln (#309) }

/// <summary>Ist AClassName gleich AAncestor oder (mit ADescendants) ein Nachfahr davon?</summary>
function IsClassOrDescendant(const AIndex: ISymbolIndex; const AClassName, AAncestor: string;
  ADescendants: Boolean): Boolean;
var
  ClassName: string;
  Location: TSymbolLocation;
  Depth: Integer;
begin
  if SameText(AClassName, AAncestor) then
    Exit(True);
  Result := False;
  if not ADescendants then
    Exit;
  ClassName := AClassName;
  for Depth := 1 to MaxDepth do
  begin
    if not FindClassSymbol(AIndex, ClassName, Location) or (Length(Location.Symbol.Ancestors) = 0) then
      Exit;
    ClassName := Location.Symbol.Ancestors[0];
    if SameText(ClassName, AAncestor) then
      Exit(True);
  end;
end;

/// <summary>Wert ohne Anführungszeichen ('Segoe UI' wird Segoe UI).</summary>
function Unquote(const AValue: string): string;
begin
  Result := Trim(AValue);
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
    Result := StringReplace(Copy(Result, 2, Length(Result) - 2), '''''', '''', [rfReplaceAll]);
end;

function IsSet(const AValue: string): Boolean;
begin
  Result := StartsStr('[', Trim(AValue)) and EndsStr(']', Trim(AValue));
end;

function SetElements(const AValue: string): TArray<string>;
var
  Inner, Element: string;
begin
  Result := nil;
  Inner := Trim(AValue);
  Inner := Copy(Inner, 2, Length(Inner) - 2);
  for Element in Inner.Split([',']) do
    if Trim(Element) <> '' then
      Result := Result + [Trim(Element)];
end;

function JoinSet(const AElements: TArray<string>): string;
begin
  Result := '[' + string.Join(', ', AElements) + ']';
end;

/// <summary>Erfüllt AActual die Regel?</summary>
function Satisfies(const ARule: TDfmPropertyRule; const AActual: string): Boolean;
var
  Actual: string;
begin
  Actual := Unquote(AActual);
  case ARule.Condition of
    TDfmCondition.Equal:
      Result := SameText(Actual, Unquote(ARule.Value));
    TDfmCondition.NotEqual:
      Result := not SameText(Actual, Unquote(ARule.Value));
    TDfmCondition.Contains, TDfmCondition.NotContains:
      begin
        if IsSet(AActual) then
          Result := MatchText(Trim(ARule.Value), SetElements(AActual))
        else
          Result := ContainsText(Actual, Unquote(ARule.Value));
        if ARule.Condition = TDfmCondition.NotContains then
          Result := not Result;
      end;
    TDfmCondition.Empty:
      Result := (Actual = '') or (Actual = '[]');
  else
    Result := (Actual <> '') and (Actual <> '[]');
  end;
end;

function ConditionText(ACondition: TDfmCondition): string;
begin
  case ACondition of
    TDfmCondition.Equal: Result := '=';
    TDfmCondition.NotEqual: Result := '<>';
    TDfmCondition.Contains: Result := 'enthält';
    TDfmCondition.NotContains: Result := 'enthält nicht';
    TDfmCondition.Empty: Result := 'ist leer';
  else
    Result := 'ist nicht leer';
  end;
end;

/// <summary>Neuer Wert nach der Korrektur; False, wenn die Bedingung keinen eindeutigen Sollwert hat.</summary>
function FixedValue(const ARule: TDfmPropertyRule; const AActual: string; AWasQuoted: Boolean;
  out AValue: string): Boolean;
var
  Elements, Kept: TArray<string>;
  Element: string;
begin
  Result := True;
  case ARule.Condition of
    TDfmCondition.Equal:
      begin
        AValue := ARule.Value;
        if AWasQuoted and not StartsStr('''', AValue) then
          AValue := QuotedStr(AValue);
      end;
    TDfmCondition.Contains:
      begin
        if (AActual <> '') and not IsSet(AActual) then
          Exit(False);
        Elements := nil;
        if AActual <> '' then
          Elements := SetElements(AActual);
        AValue := JoinSet(Elements + [Trim(ARule.Value)]);
      end;
    TDfmCondition.NotContains:
      begin
        if not IsSet(AActual) then
          Exit(False);
        Kept := nil;
        for Element in SetElements(AActual) do
          if not SameText(Element, Trim(ARule.Value)) then
            Kept := Kept + [Element];
        AValue := JoinSet(Kept);
      end;
  else
    Result := False;
  end;
end;

/// <summary>Gespeicherte Property APath des Objekts.</summary>
function StoredProperty(AObject: TDfmObject; const APath: string; out AProperty: TDfmProperty): Boolean;
var
  Item: TDfmProperty;
begin
  for Item in AObject.Properties do
    if SameText(Item.Name, APath) then
    begin
      AProperty := Item;
      Exit(True);
    end;
  Result := False;
end;

function IndentOf(const ALine: string): string;
var
  Index: Integer;
begin
  Index := 1;
  while (Index <= Length(ALine)) and CharInSet(ALine[Index], [' ', #9]) do
    Inc(Index);
  Result := Copy(ALine, 1, Index - 1);
end;

class function TFormSymbols.PropertyViolations(const AText, AFileName: string;
  const ARules: TArray<TDfmPropertyRule>; const AIndex: ISymbolIndex;
  const AReadText: TMemberReadText): TArray<TFormPropertyViolation>;
var
  View: TFormView;
  Found: TArray<TFormPropertyViolation>;
  Active: TArray<Integer>;

  procedure Check(AObject: TDfmObject; ARuleIndex: Integer; const AClassName: string);
  var
    Rule: TDfmPropertyRule;
    Stored: TDfmProperty;
    Member: TPublishedMember;
    HasStored: Boolean;
    Actual, NewValue, HeaderLine: string;
    Violation: TFormPropertyViolation;
  begin
    Rule := ARules[ARuleIndex];
    HasStored := StoredProperty(AObject, Rule.PropertyPath, Stored);
    if HasStored then
      Actual := Trim(Stored.Value)
    else
    begin
      // Geerbte Objekte haben den Wert aus dem Vorfahren; gemeldet wird dort.
      if AObject.Kind = TDfmObjectKind.Inherited_ then
        Exit;
      if not ResolveProperty(AIndex, AReadText, AClassName, Rule.PropertyPath, Member) then
        Exit;
      Actual := Member.DefaultValue;
    end;
    if Satisfies(Rule, Actual) then
      Exit;
    Violation := Default(TFormPropertyViolation);
    Violation.RuleIndex := ARuleIndex;
    Violation.Severity := Rule.Severity;
    Violation.Message := Rule.Message;
    if Violation.Message = '' then
      Violation.Message := Format('%s.%s %s %s (ist: %s)', [Rule.ClassName, Rule.PropertyPath,
        ConditionText(Rule.Condition), Rule.Value, IfThen(Actual = '', 'leer', Actual)]);
    if HasStored then
      Violation.Range := TTextRange.Create(Stored.NameRange.StartPos, Stored.ValueRange.EndPos)
    else
      Violation.Range := TTextRange.Create(AObject.Range.StartPos, AObject.TypeRange.EndPos);
    if (Rule.Fix <> TDfmFixMode.None) and FixedValue(Rule, Actual, StartsStr('''', Actual), NewValue) then
    begin
      Violation.HasFix := True;
      Violation.Safe := Rule.Fix = TDfmFixMode.Auto;
      if HasStored then
        Violation.Fix := TRuleEdit.Create(Stored.ValueRange, NewValue)
      else
      begin
        // Neue Zeile direkt unter dem Kopf des Objekts.
        HeaderLine := View.Lines[AObject.Range.StartPos.Line];
        Violation.Fix := TRuleEdit.Create(TTextRange.Create(AObject.Range.StartPos.Line, Length(HeaderLine),
          AObject.Range.StartPos.Line, Length(HeaderLine)), View.LineBreak + IndentOf(HeaderLine) + '  ' +
          Rule.PropertyPath + ' = ' + NewValue);
      end;
    end;
    Found := Found + [Violation];
  end;

  procedure Visit(AObject: TDfmObject);
  var
    ClassName: string;
    RuleIndex: Integer;
    Child: TDfmObject;
  begin
    ClassName := View.ClassOf(AObject, AIndex, AReadText);
    if ClassName <> '' then
      for RuleIndex in Active do
        if IsClassOrDescendant(AIndex, ClassName, ARules[RuleIndex].ClassName,
          ARules[RuleIndex].IncludeDescendants) then
          Check(AObject, RuleIndex, ClassName);
    for Child in AObject.Children do
      Visit(Child);
  end;

var
  RuleIndex: Integer;
  Pattern: string;
  Excluded: Boolean;
begin
  Found := nil;
  Active := nil;
  for RuleIndex := 0 to High(ARules) do
  begin
    if ARules[RuleIndex].Severity = TRuleSeverity.Off then
      Continue;
    Excluded := False;
    for Pattern in ARules[RuleIndex].Exclude do
      if MatchesGlob(Pattern, AFileName) then
        Excluded := True;
    if not Excluded then
      Active := Active + [RuleIndex];
  end;
  if Length(Active) = 0 then
    Exit(nil);
  View := TFormView.Create(AText);
  try
    if View.Document.Root <> nil then
      Visit(View.Document.Root);
  finally
    View.Free;
  end;
  Result := Found;
end;

class function TFormSymbols.RuleProblems(const ARules: TArray<TDfmPropertyRule>; const AIndex: ISymbolIndex;
  const AReadText: TMemberReadText): TArray<TFormPropertyRuleProblem>;
var
  Index: Integer;
  Location: TSymbolLocation;
  Member: TPublishedMember;
  Problem: TFormPropertyRuleProblem;
begin
  Result := nil;
  if AIndex = nil then
    Exit;
  for Index := 0 to High(ARules) do
  begin
    Problem.RuleIndex := Index;
    Problem.Message := '';
    if not FindClassSymbol(AIndex, ARules[Index].ClassName, Location) then
      Problem.Message := Format('Unbekannte Klasse "%s"', [ARules[Index].ClassName])
    else if not ResolveProperty(AIndex, AReadText, ARules[Index].ClassName, ARules[Index].PropertyPath, Member) then
      Problem.Message := Format('%s hat keine published-Property "%s"', [ARules[Index].ClassName,
        ARules[Index].PropertyPath]);
    if Problem.Message <> '' then
      Result := Result + [Problem];
  end;
end;

end.
