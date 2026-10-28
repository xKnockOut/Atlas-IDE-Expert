unit Atlas.Common.Rules.Builtin.DfmProperties;

// Eigenschaftsregeln für Formulardateien (#309), Regel dfm-property: Vorgaben
// für Komponenten-Properties aus "dfmPropertyRules" in atlas.json, z. B. alle
// TLabel mit Transparent = True oder kein Formular mit Position = poDesigned.
//
// Wie die übrigen DFM-Regeln liest die Regel TRuleContext.FormText (#123) über
// das Formularmodell (#267) und meldet in der Unit: am Feld der Komponente bzw.
// an der Formularklasse. Ist eine Property nicht gespeichert, gilt ihr default
// aus der Deklaration in der Klasse bzw. ihren Vorfahren (ohne default: False,
// 0, [] oder ''). Objekte aus dem Vorfahrenformular (inherited) werden nur
// gemeldet, wenn dieses Formular den Wert selbst setzt; sonst gehört der
// Verstoß zum Vorfahren. Verschachtelte Pfade (Font.Name) folgen dem Typ der
// Zwischen-Property (TFont); hat eine Property im Pfad "stored" mit einer
// Funktion oder False, ist der nicht gespeicherte Wert unbekannt und die Regel
// schweigt.
//
// Schnellkorrektur (#309): Mit bekannter Formulardatei (TRuleContext.FormFile)
// ändert sie die Formulardatei: Sollwert setzen (vorhandenen Wert ersetzen oder
// eine Zeile nach den Properties des Objekts einfügen), Set-Element ergänzen
// bzw. entfernen, leeren. Für <> und notEmpty gibt es keinen eindeutigen
// Sollwert, also keine Korrektur. fix: auto macht sie sicher (source.fixAll),
// none unterdrückt sie. Binäre Formulare werden nicht korrigiert.
//
// ConfigurationIssues meldet Regeln mit unbekannter Klasse oder Property für
// atlas.json (Abnahme #309), sobald der Index die Klasse kennen müsste.

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TDfmPropertyCheckRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Erfüllt der Ist-Wert AActual die Bedingung ACondition mit dem Sollwert AExpected?</summary>
    class function Satisfies(ACondition: TDfmCondition; const AActual, AExpected: string): Boolean; static;
    /// <summary>Wert nach "default" in einer Property-Deklaration; False ohne Angabe.</summary>
    class function DeclaredDefault(const ADeclaration: string; out AValue: string): Boolean; static;
    /// <summary>Regeln aus ARules, deren Klasse oder Property AIndex nicht kennt, als Meldungen an
    /// ClassRange bzw. PropertyRange (Warnungen in atlas.json). Ohne Index keine. AReadFile liest die
    /// Quellen des Index für Typ und default der Properties; nil = nur Namen prüfen.</summary>
    class function ConfigurationIssues(const ARules: TArray<TDfmPropertyRule>; const AIndex: ISymbolIndex;
      const AReadFile: TRuleFileReader): TArray<TConfigurationIssue>; static;
    /// <summary>Wert als DFM-Text: Strings in Hochkommas, Zeichen außerhalb ASCII als #Code.</summary>
    class function DfmString(const AValue: string): string; static;
  end;

procedure RegisterDfmPropertyRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.FormModel,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Rules.Derived,
  Atlas.Text.Lines;

const
  MaxDepth = 30;
  // Typ der ersten Property-Deklaration, auch mit Index: property Items[I: Integer]: string.
  PropertyTypePattern = '\bproperty\s+\w+\s*(?:\[[^\]]*\])?\s*:\s*([\w.]+)';
  DefaultPattern = '\bdefault\s+([^;]+?)\s*;';
  StoredPattern = '\bstored\s+([\w.]+)';
  StringTypes: array[0..6] of string = ('string', 'UnicodeString', 'WideString', 'AnsiString', 'TCaption',
    'TFontName', 'TFileName');

/// <summary>Wert nach "default" in ADeclaration über das kompilierte Muster ARegEx.</summary>
function DefaultOf(const ARegEx: TRegEx; const ADeclaration: string; out AValue: string): Boolean;
var
  Match: TMatch;
begin
  Match := ARegEx.Match(ADeclaration);
  Result := Match.Success;
  if Result then
    AValue := Trim(Match.Groups[1].Value)
  else
    AValue := '';
end;

type
  /// <summary>Was die Deklarationen einer Property über ihren nicht gespeicherten Wert sagen.</summary>
  TPropertyInfo = record
    /// <summary>Die Property ist in der Klasse oder einem Vorfahren deklariert.</summary>
    Found: Boolean;
    /// <summary>Typ aus der ersten Deklaration mit Typ; '' ohne.</summary>
    TypeName: string;
    HasDefault: Boolean;
    DefaultValue: string;
    NoDefault: Boolean;
    /// <summary>"stored" mit Funktion oder False: Der nicht gespeicherte Wert ist unbekannt.</summary>
    StoredUnknown: Boolean;
  end;

  /// <summary>Ein Prüflauf: Klassenketten und Property-Deklarationen über den Index.</summary>
  TPropertyChecker = class
  private
    FContext: TRuleContext;
    FUnit: TUnitIndex;
    FLines: TDictionary<string, TArray<string>>;
    // Je Prüfung einmal kompiliert (Review P-11). TRegEx hält Zustand und ist nicht
    // threadsicher; Regeln laufen parallel, daher keine globale Instanz.
    FPropertyType: TRegEx;
    FDefault: TRegEx;
    FStored: TRegEx;
    function FileLines(const AFileName: string): TArray<string>;
    function DeclarationText(const ALocation: TSymbolLocation): string;
    /// <summary>Symbole AName aus der geprüften Unit (FileName '') und dem Index.</summary>
    function Members(const AName: string): TArray<TSymbolLocation>;
    /// <summary>Deklarationen von AName in AClassName und den Vorfahren, die jüngste zuerst.</summary>
    function PropertyInfo(const AClassName, AName: string): TPropertyInfo;
  public
    /// <summary>AUnit: die geprüfte Unit; ihre Klassen (z. B. die Formularklasse) stehen evtl. nicht im Index.</summary>
    constructor Create(const AContext: TRuleContext; const AUnit: TUnitIndex);
    destructor Destroy; override;
    function FindClass(const AName: string; out ALocation: TSymbolLocation): Boolean;
    function IsClassOrDescendant(const AClassName, ABase: string; ADescendants: Boolean): Boolean;
    /// <summary>Wert der nicht gespeicherten Property APath (auch Font.Name) von AClassName; False, wenn
    /// er unbekannt ist. ATypeName: Typ der letzten Property, '' wenn unbekannt.</summary>
    function DefaultValue(const AClassName, APath: string; out AValue, ATypeName: string): Boolean;
    /// <summary>Gibt es APath (auch Font.Name) an AClassName? AMissing: der erste unbekannte Teil.</summary>
    function HasProperty(const AClassName, APath: string; out AMissing: string): Boolean;
  end;

{ TPropertyChecker }

constructor TPropertyChecker.Create(const AContext: TRuleContext; const AUnit: TUnitIndex);
begin
  inherited Create;
  FContext := AContext;
  FUnit := AUnit;
  FLines := TDictionary<string, TArray<string>>.Create;
  FPropertyType := TRegEx.Create(PropertyTypePattern, [roIgnoreCase, roCompiled]);
  FDefault := TRegEx.Create(DefaultPattern, [roIgnoreCase, roCompiled]);
  FStored := TRegEx.Create(StoredPattern, [roIgnoreCase, roCompiled]);
end;

destructor TPropertyChecker.Destroy;
begin
  FLines.Free;
  inherited;
end;

function TPropertyChecker.FileLines(const AFileName: string): TArray<string>;
var
  Data: TBytes;
  Text: string;
  mFormat: TFileFormat;
begin
  if FLines.TryGetValue(UpperCase(AFileName), Result) then
    Exit;
  Result := nil;
  // '' steht für die geprüfte Unit selbst.
  if AFileName = '' then
    Result := FContext.Text.Replace(#13#10, #10).Split([#10])
  else if Assigned(FContext.ReadFile) and FContext.ReadFile(AFileName, Data) then
  begin
    // Dieselbe Erkennung wie überall (#1327): BOM, sonst nur ganz gültiges UTF-8 als UTF-8, sonst ANSI.
    Text := TFileEncoding.Decode(Data, mFormat);
    Result := Text.Replace(#13#10, #10).Split([#10]);
  end;
  FLines.Add(UpperCase(AFileName), Result);
end;

function TPropertyChecker.FindClass(const AName: string; out ALocation: TSymbolLocation): Boolean;
var
  Location: TSymbolLocation;
  Symbol: TIndexSymbol;
begin
  for Symbol in FUnit.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.ClassType) and (Symbol.Container = '') and SameText(Symbol.Name, AName) then
    begin
      ALocation.UnitName := FUnit.UnitName;
      ALocation.FileName := '';
      ALocation.Symbol := Symbol;
      Exit(True);
    end;
  if FContext.Index = nil then
    Exit(False);
  for Location in FContext.Index.FindSymbols(AName) do
    if (Location.Symbol.Kind = TIndexSymbolKind.ClassType) and (Location.Symbol.Container = '') then
    begin
      ALocation := Location;
      Exit(True);
    end;
  Result := False;
end;

function TPropertyChecker.IsClassOrDescendant(const AClassName, ABase: string; ADescendants: Boolean): Boolean;
var
  Name: string;
  Location: TSymbolLocation;
  Depth: Integer;
begin
  if SameText(AClassName, ABase) then
    Exit(True);
  Result := False;
  if not ADescendants then
    Exit;
  Name := AClassName;
  for Depth := 1 to MaxDepth do
  begin
    if not FindClass(Name, Location) or (Length(Location.Symbol.Ancestors) = 0) then
      Exit;
    Name := Location.Symbol.Ancestors[0];
    if SameText(Name, ABase) then
      Exit(True);
  end;
end;

function TPropertyChecker.Members(const AName: string): TArray<TSymbolLocation>;
var
  Symbol: TIndexSymbol;
  Location: TSymbolLocation;
begin
  Result := nil;
  for Symbol in FUnit.Symbols do
    if SameText(Symbol.Name, AName) then
    begin
      Location.UnitName := FUnit.UnitName;
      Location.FileName := '';
      Location.Symbol := Symbol;
      Result := Result + [Location];
    end;
  if FContext.Index <> nil then
    Result := Result + FContext.Index.FindSymbols(AName);
end;

function TPropertyChecker.DeclarationText(const ALocation: TSymbolLocation): string;
var
  Lines: TArray<string>;
  Line: Integer;
begin
  Result := '';
  Lines := FileLines(ALocation.FileName);
  for Line := ALocation.Symbol.Range.StartPos.Line to ALocation.Symbol.Range.EndPos.Line do
    if (Line >= 0) and (Line <= High(Lines)) then
      Result := Result + ' ' + Trim(Lines[Line]);
  Result := Trim(Result);
end;

function TPropertyChecker.PropertyInfo(const AClassName, AName: string): TPropertyInfo;
var
  Name, Declaration, Stored: string;
  Location, Member: TSymbolLocation;
  Depth: Integer;
  Match: TMatch;
  Decided: Boolean;
begin
  Result := Default(TPropertyInfo);
  Decided := False;
  Name := AClassName;
  for Depth := 1 to MaxDepth do
  begin
    if not FindClass(Name, Location) then
      Exit;
    for Member in Members(AName) do
      if (Member.Symbol.Kind = TIndexSymbolKind.Property_) and SameText(Member.Symbol.Container, Name) then
      begin
        Result.Found := True;
        Declaration := DeclarationText(Member);
        // Die jüngste Angabe gilt; eine Hochstufung ohne Angaben (property X;) erbt sie.
        if not Decided then
        begin
          Match := FStored.Match(Declaration);
          if Match.Success then
          begin
            Stored := Match.Groups[1].Value;
            Result.StoredUnknown := not SameText(Stored, 'True');
            Decided := True;
          end;
          if ContainsText(Declaration, 'nodefault') then
          begin
            Result.NoDefault := True;
            Decided := True;
          end
          else if DefaultOf(FDefault, Declaration, Result.DefaultValue) then
          begin
            Result.HasDefault := True;
            Decided := True;
          end;
        end;
        // Typ steht nur in der ersten Deklaration; eine Hochstufung (property X;) erbt ihn.
        Match := FPropertyType.Match(Declaration);
        if Match.Success then
        begin
          Result.TypeName := Match.Groups[1].Value;
          Exit;
        end;
        Break;
      end;
    if Length(Location.Symbol.Ancestors) = 0 then
      Exit;
    Name := Location.Symbol.Ancestors[0];
  end;
end;

function TPropertyChecker.DefaultValue(const AClassName, APath: string; out AValue, ATypeName: string): Boolean;
var
  Parts: TArray<string>;
  Name: string;
  Index: Integer;
  Info: TPropertyInfo;
begin
  Result := False;
  AValue := '';
  ATypeName := '';
  Parts := APath.Split(['.']);
  if Length(Parts) = 0 then
    Exit;
  // Verschachtelt (Font.Name): über den Typ jeder Zwischen-Property zur Klasse des letzten Teils.
  Name := AClassName;
  for Index := 0 to High(Parts) - 1 do
  begin
    Info := PropertyInfo(Name, Parts[Index]);
    // Nicht gespeichertes Objekt (stored IsFontStored, ParentFont): Werte kommen von anderswo.
    if not Info.Found or (Info.TypeName = '') or Info.StoredUnknown then
      Exit;
    Name := Info.TypeName;
  end;
  Info := PropertyInfo(Name, Parts[High(Parts)]);
  ATypeName := Info.TypeName;
  if not Info.Found or Info.StoredUnknown or Info.NoDefault then
    Exit;
  if Info.HasDefault then
  begin
    AValue := Info.DefaultValue;
    Exit(True);
  end;
  // Ohne default speichert die VCL alles außer dem Nullwert des Typs.
  if SameText(Info.TypeName, 'Boolean') then
    AValue := 'False'
  else if MatchText(Info.TypeName, ['Integer', 'Cardinal', 'Byte', 'Word', 'SmallInt', 'ShortInt', 'Int64',
    'UInt64', 'NativeInt', 'NativeUInt', 'LongInt', 'LongWord', 'TColor']) then
    AValue := '0'
  else if MatchText(Info.TypeName, StringTypes) then
    AValue := ''
  else
    Exit;
  Result := True;
end;

function TPropertyChecker.HasProperty(const AClassName, APath: string; out AMissing: string): Boolean;
var
  Name, Part: string;
  Info: TPropertyInfo;
  Location: TSymbolLocation;
begin
  AMissing := '';
  Name := AClassName;
  for Part in APath.Split(['.']) do
  begin
    // Typ ohne Klasse im Index (z. B. ein Aufzählungstyp vor dem letzten Teil): nicht weiter prüfbar.
    if not FindClass(Name, Location) then
      Exit(True);
    Info := PropertyInfo(Name, Part);
    if not Info.Found then
    begin
      AMissing := Part;
      Exit(False);
    end;
    Name := Info.TypeName;
    if Name = '' then
      Exit(True);
  end;
  Result := True;
end;

{ TDfmPropertyCheckRule }

function TDfmPropertyCheckRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('dfm-property', TRuleSeverity.Warning,
    'Komponenten-Property weicht von einer Eigenschaftsregel aus atlas.json ab');
end;

class function TDfmPropertyCheckRule.DeclaredDefault(const ADeclaration: string; out AValue: string): Boolean;
begin
  Result := DefaultOf(TRegEx.Create(DefaultPattern, [roIgnoreCase]), ADeclaration, AValue);
end;

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

function IsEmptyValue(const AValue: string): Boolean;
begin
  Result := (Trim(AValue) = '') or (Unquote(AValue) = '') or (IsSet(AValue) and (Length(SetElements(AValue)) = 0));
end;

function SameValue(const AActual, AExpected: string): Boolean;
var
  Element: string;
  Actual, Expected: TArray<string>;
begin
  if IsSet(AActual) and IsSet(AExpected) then
  begin
    Actual := SetElements(AActual);
    Expected := SetElements(AExpected);
    if Length(Actual) <> Length(Expected) then
      Exit(False);
    for Element in Expected do
      if not MatchText(Element, Actual) then
        Exit(False);
    Exit(True);
  end;
  Result := SameText(Unquote(AActual), Unquote(AExpected));
end;

function ContainsValue(const AActual, AExpected: string): Boolean;
begin
  if IsSet(AActual) then
    Result := MatchText(Trim(AExpected), SetElements(AActual))
  else
    Result := ContainsText(Unquote(AActual), Unquote(AExpected));
end;

class function TDfmPropertyCheckRule.Satisfies(ACondition: TDfmCondition; const AActual, AExpected: string): Boolean;
begin
  case ACondition of
    TDfmCondition.Equal:
      Result := SameValue(AActual, AExpected);
    TDfmCondition.NotEqual:
      Result := not SameValue(AActual, AExpected);
    TDfmCondition.Contains:
      Result := ContainsValue(AActual, AExpected);
    TDfmCondition.NotContains:
      Result := not ContainsValue(AActual, AExpected);
    TDfmCondition.Empty:
      Result := IsEmptyValue(AActual);
  else
    Result := not IsEmptyValue(AActual);
  end;
end;

function DefaultMessage(const ARule: TDfmPropertyRule; const AObject: TDfmObject; const AActual: string): string;
var
  Actual: string;
begin
  Actual := AActual;
  if Actual = '' then
    Actual := '''''';
  case ARule.Condition of
    TDfmCondition.Equal:
      Result := Format('%s soll %s sein, ist %s', [ARule.PropertyPath, ARule.Value, Actual]);
    TDfmCondition.NotEqual:
      Result := Format('%s darf nicht %s sein', [ARule.PropertyPath, ARule.Value]);
    TDfmCondition.Contains:
      Result := Format('%s soll %s enthalten, ist %s', [ARule.PropertyPath, ARule.Value, Actual]);
    TDfmCondition.NotContains:
      Result := Format('%s darf %s nicht enthalten', [ARule.PropertyPath, ARule.Value]);
    TDfmCondition.Empty:
      Result := Format('%s soll leer sein, ist %s', [ARule.PropertyPath, Actual]);
  else
    Result := Format('%s darf nicht leer sein', [ARule.PropertyPath]);
  end;
  Result := Format('%s (%s): %s', [AObject.Name, AObject.TypeName, Result]);
end;

function IsExcluded(const ARule: TDfmPropertyRule; const ARelativePath: string): Boolean;
var
  Pattern: string;
begin
  if ARelativePath = '' then
    Exit(False);
  for Pattern in ARule.Exclude do
    if MatchesGlob(Pattern, ARelativePath) or MatchesGlob(Pattern, ChangeFileExt(ARelativePath, '.dfm')) or
      MatchesGlob(Pattern, ChangeFileExt(ARelativePath, '.fmx')) then
      Exit(True);
  Result := False;
end;

procedure CollectObjects(AObject: TDfmObject; var AObjects: TArray<TDfmObject>);
var
  Child: TDfmObject;
begin
  if (AObject.Kind <> TDfmObjectKind.Item) and (AObject.TypeName <> '') then
    AObjects := AObjects + [AObject];
  for Child in AObject.Children do
    CollectObjects(Child, AObjects);
end;

class function TDfmPropertyCheckRule.DfmString(const AValue: string): string;
var
  Ch: Char;
  Quoted: Boolean;
begin
  // Wie die IDE: druckbares ASCII in Hochkommas, alles andere als #Code.
  Result := '';
  Quoted := False;
  for Ch in AValue do
    if (Ord(Ch) >= 32) and (Ord(Ch) < 127) then
    begin
      if not Quoted then
        Result := Result + '''';
      Quoted := True;
      if Ch = '''' then
        Result := Result + ''''''
      else
        Result := Result + Ch;
    end
    else
    begin
      if Quoted then
        Result := Result + '''';
      Quoted := False;
      Result := Result + '#' + IntToStr(Ord(Ch));
    end;
  if Quoted then
    Result := Result + '''';
  if Result = '' then
    Result := '''''';
end;

function IsIdentifierLike(const AValue: string): Boolean;
var
  Ch: Char;
begin
  Result := AValue <> '';
  for Ch in AValue do
    if not CharInSet(Ch, ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.', '$']) then
      Exit(False);
end;

/// <summary>Sollwert als DFM-Text. AStringType: die Property ist ein String (gespeichert in Hochkommas
/// oder vom Typ string); sonst bleiben Bezeichner, Zahlen und Mengen, wie sie sind.</summary>
function DfmValue(const AValue: string; AStringType: Boolean): string;
begin
  Result := Trim(AValue);
  if StartsStr('''', Result) or StartsStr('#', Result) then
    Exit;
  if AStringType or not (IsSet(Result) or IsIdentifierLike(Result)) then
    Result := TDfmPropertyCheckRule.DfmString(AValue);
end;

function JoinSet(const AElements: TArray<string>): string;
begin
  Result := '[' + string.Join(', ', AElements) + ']';
end;

/// <summary>Neuer Wert, der die Regel erfüllt; False, wenn es keinen eindeutigen gibt.</summary>
function TargetValue(const ARule: TDfmPropertyRule; const AActual: string; AStringType: Boolean;
  out AValue, ATitle: string): Boolean;
var
  Kept: TArray<string>;
  Element: string;
  IsSetValue: Boolean;
begin
  Result := True;
  AValue := '';
  ATitle := '';
  IsSetValue := IsSet(AActual);
  case ARule.Condition of
    TDfmCondition.Equal:
      begin
        AValue := DfmValue(ARule.Value, AStringType);
        ATitle := Format('%s = %s in der Formulardatei setzen', [ARule.PropertyPath, AValue]);
      end;
    TDfmCondition.Contains:
      begin
        if not IsSetValue then
          Exit(False);
        AValue := JoinSet(SetElements(AActual) + [Trim(ARule.Value)]);
        ATitle := Format('%s in %s ergänzen', [Trim(ARule.Value), ARule.PropertyPath]);
      end;
    TDfmCondition.NotContains:
      begin
        if not IsSetValue then
          Exit(False);
        Kept := nil;
        for Element in SetElements(AActual) do
          if not SameText(Element, Trim(ARule.Value)) then
            Kept := Kept + [Element];
        AValue := JoinSet(Kept);
        ATitle := Format('%s aus %s entfernen', [Trim(ARule.Value), ARule.PropertyPath]);
      end;
    TDfmCondition.Empty:
      begin
        if IsSetValue then
          AValue := '[]'
        else if AStringType or StartsStr('''', Trim(AActual)) or StartsStr('#', Trim(AActual)) then
          AValue := ''''''
        else
          Exit(False);
        ATitle := Format('%s in der Formulardatei leeren', [ARule.PropertyPath]);
      end;
  else
    // <> und notEmpty: kein eindeutiger Sollwert.
    Result := False;
  end;
end;

function LeadingSpaces(const ALine: string): string;
var
  Count: Integer;
begin
  Count := 0;
  while (Count < Length(ALine)) and CharInSet(ALine[Count + 1], [' ', #9]) do
    Inc(Count);
  Result := Copy(ALine, 1, Count);
end;

/// <summary>Edit in der Formulardatei: gespeicherten Wert ersetzen oder eine Zeile nach den Properties
/// des Objekts einfügen.</summary>
function FormEdit(const AFormLines: TArray<string>; const ALineBreak: string; AObject: TDfmObject;
  const AName, AValue: string; AStored: Boolean; const AProperty: TDfmProperty): TRuleEdit;
var
  Item: TDfmProperty;
  Line: Integer;
  Indent: string;
begin
  if AStored then
    Exit(TRuleEdit.Create(AProperty.ValueRange, AValue));
  // Hinter der letzten Property, vor den Kindobjekten; ohne Properties hinter der Kopfzeile.
  Line := AObject.TypeRange.EndPos.Line;
  for Item in AObject.Properties do
    if Item.ValueRange.EndPos.Line > Line then
      Line := Item.ValueRange.EndPos.Line;
  Indent := '';
  if (AObject.Range.StartPos.Line >= 0) and (AObject.Range.StartPos.Line <= High(AFormLines)) then
    Indent := LeadingSpaces(AFormLines[AObject.Range.StartPos.Line]);
  Result := TRuleEdit.Create(TTextRange.Create(Line + 1, 0, Line + 1, 0),
    Indent + '  ' + AName + ' = ' + AValue + ALineBreak);
end;

procedure TDfmPropertyCheckRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Model: TFormModel;
  Checker: TPropertyChecker;
  Objects: TArray<TDfmObject>;
  Obj: TDfmObject;
  Rule: TDfmPropertyRule;
  Prop, Found: TDfmProperty;
  Stored, StringType, CanFix: Boolean;
  Actual, Message, TypeName, Target, Title, LineBreak: string;
  UnitIndex: TUnitIndex;
  Symbol: TIndexSymbol;
  ClassRange, Range: TTextRange;
  Cache: IRuleDerivedCache;
  Fixes: TArray<TRuleFix>;
  Fix: TRuleFix;
  FormLines: TArray<string>;
begin
  if (Length(AContext.DfmPropertyRules) = 0) or (AContext.FormText = '') or (AContext.Tree = nil) then
    Exit;
  // Gemeldet wird in der Unit: am Feld der Komponente, sonst an der Formularklasse.
  // Den Index der Datei teilt der Lauf mit den anderen Regeln (Review P-03).
  Cache := TRuleDerived.Open(AContext);
  UnitIndex := TRuleDerived.UnitIndex(Cache, AContext);
  Model := TFormModel.Create(AContext.FormText);
  Checker := TPropertyChecker.Create(AContext, UnitIndex);
  try
    if (Model.Document.Root = nil) or (Model.FormClass = '') then
      Exit;
    ClassRange := Default(TTextRange);
    for Symbol in UnitIndex.Symbols do
      if (Symbol.Kind = TIndexSymbolKind.ClassType) and (Symbol.Container = '') and
        SameText(Symbol.Name, Model.FormClass) then
        ClassRange := Symbol.SelectionRange;
    if ClassRange.StartPos = ClassRange.EndPos then
      Exit;
    // Korrigiert wird nur eine Text-Formulardatei mit bekanntem Pfad.
    CanFix := (AContext.FormFile <> '') and not Model.Binary;
    LineBreak := TTextLines.LineBreakOf(AContext.FormText);
    FormLines := nil;
    if CanFix then
      FormLines := AContext.FormText.Replace(#13#10, #10).Split([#10]);
    Objects := nil;
    CollectObjects(Model.Document.Root, Objects);
    for Rule in AContext.DfmPropertyRules do
    begin
      if (Rule.Severity = TRuleSeverity.Off) or IsExcluded(Rule, AContext.RelativePath) then
        Continue;
      for Obj in Objects do
      begin
        if not Checker.IsClassOrDescendant(Obj.TypeName, Rule.ClassName, Rule.IncludeDescendants) then
          Continue;
        Stored := False;
        Actual := '';
        TypeName := '';
        Found := Default(TDfmProperty);
        for Prop in Obj.Properties do
          if SameText(Prop.Name, Rule.PropertyPath) then
          begin
            Stored := True;
            Found := Prop;
            Actual := Trim(Prop.Value);
            Break;
          end;
        // Aus dem Vorfahrenformular und hier nicht gesetzt: Sache des Vorfahren.
        if not Stored and (Obj.Kind = TDfmObjectKind.Inherited_) then
          Continue;
        if not Stored and not Checker.DefaultValue(Obj.TypeName, Rule.PropertyPath, Actual, TypeName) then
          Continue;
        if Satisfies(Rule.Condition, Actual, Rule.Value) then
          Continue;
        Range := ClassRange;
        if Obj <> Model.Document.Root then
          for Symbol in UnitIndex.Symbols do
            if (Symbol.Kind = TIndexSymbolKind.Field) and SameText(Symbol.Container, Model.FormClass) and
              SameText(Symbol.Name, Obj.Name) then
            begin
              Range := Symbol.SelectionRange;
              Break;
            end;
        if Rule.Message <> '' then
          Message := Format('%s (%s): %s', [Obj.Name, Obj.TypeName, Rule.Message])
        else
          Message := DefaultMessage(Rule, Obj, Actual);
        Fixes := nil;
        if CanFix and (Rule.Fix <> TDfmFixMode.None) then
        begin
          if Stored then
            StringType := StartsStr('''', Actual) or StartsStr('#', Actual)
          else
            StringType := MatchText(TypeName, StringTypes);
          if TargetValue(Rule, Actual, StringType, Target, Title) then
          begin
            Fix := TRuleFix.Create(Format('%s: %s', [Obj.Name, Title]),
              [FormEdit(FormLines, LineBreak, Obj, Rule.PropertyPath, Target, Stored, Found)],
              Rule.Fix = TDfmFixMode.Auto);
            Fix.FileName := AContext.FormFile;
            Fixes := [Fix];
          end;
        end;
        AReport.AddWithSeverity(Range, Message, Rule.Severity, Fixes);
      end;
    end;
  finally
    Checker.Free;
    Model.Free;
  end;
end;

class function TDfmPropertyCheckRule.ConfigurationIssues(const ARules: TArray<TDfmPropertyRule>;
  const AIndex: ISymbolIndex; const AReadFile: TRuleFileReader): TArray<TConfigurationIssue>;
var
  Context: TRuleContext;
  Checker: TPropertyChecker;
  Rule: TDfmPropertyRule;
  Location: TSymbolLocation;
  Missing: string;
  Issue: TConfigurationIssue;
begin
  Result := nil;
  if (AIndex = nil) or (Length(ARules) = 0) then
    Exit;
  Context := Default(TRuleContext);
  Context.Index := AIndex;
  Context.ReadFile := AReadFile;
  Checker := TPropertyChecker.Create(Context, Default(TUnitIndex));
  try
    for Rule in ARules do
    begin
      if Rule.ClassName = '' then
        Continue;
      Issue := Default(TConfigurationIssue);
      if not Checker.FindClass(Rule.ClassName, Location) then
      begin
        Issue.Range := Rule.ClassRange;
        Issue.Message := Format('Klasse "%s" ist im Index unbekannt; die Eigenschaftsregel greift nie',
          [Rule.ClassName]);
      end
      else if (Rule.PropertyPath <> '') and not Checker.HasProperty(Rule.ClassName, Rule.PropertyPath, Missing) then
      begin
        Issue.Range := Rule.PropertyRange;
        Issue.Message := Format('%s hat keine Property "%s"; die Eigenschaftsregel greift nie',
          [Rule.ClassName, Missing]);
      end
      else
        Continue;
      Result := Result + [Issue];
    end;
  finally
    Checker.Free;
  end;
end;

procedure RegisterDfmPropertyRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TDfmPropertyCheckRule.Create);
end;

end.
