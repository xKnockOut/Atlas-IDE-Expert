unit Argus.Common.Rules.Builtin.DfmProperties;

// Eigenschaftsregeln für Formulardateien (#309), Regel dfm-property: Vorgaben
// für Komponenten-Properties aus "dfmPropertyRules" in argus.json, z. B. alle
// TLabel mit Transparent = True oder kein Formular mit Position = poDesigned.
//
// Wie die übrigen DFM-Regeln liest die Regel TRuleContext.FormText (#123) über
// das Formularmodell (#267) und meldet in der Unit: am Feld der Komponente bzw.
// an der Formularklasse. Ist eine Property nicht gespeichert, gilt ihr default
// aus der Deklaration in der Klasse bzw. ihren Vorfahren (ohne default: False,
// 0, [] oder ''). Objekte aus dem Vorfahrenformular (inherited) werden nur
// gemeldet, wenn dieses Formular den Wert selbst setzt; sonst gehört der
// Verstoß zum Vorfahren. Verschachtelte Pfade (Font.Name) zählen nur, wenn sie
// gespeichert sind.

interface

uses
  System.SysUtils,
  Argus.Common.Configuration.Contract,
  Argus.Common.Rules.Contract,
  Argus.Common.Rules.Registry;

type
  TDfmPropertyCheckRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Erfüllt der Ist-Wert AActual die Bedingung ACondition mit dem Sollwert AExpected?</summary>
    class function Satisfies(ACondition: TDfmCondition; const AActual, AExpected: string): Boolean; static;
    /// <summary>Wert nach "default" in einer Property-Deklaration; False ohne Angabe.</summary>
    class function DeclaredDefault(const ADeclaration: string; out AValue: string): Boolean; static;
  end;

procedure RegisterDfmPropertyRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  Argus.Common.Documents.Contract,
  Argus.Common.Index.Contract,
  Argus.Common.Index.Extractor,
  Argus.Common.Dfm.Contract,
  Argus.Common.Dfm.FormModel;

const
  MaxDepth = 30;

type
  /// <summary>Ein Prüflauf: Klassenketten und Property-Deklarationen über den Index.</summary>
  TPropertyChecker = class
  private
    FContext: TRuleContext;
    FUnit: TUnitIndex;
    FLines: TDictionary<string, TArray<string>>;
    function FileLines(const AFileName: string): TArray<string>;
    function FindClass(const AName: string; out ALocation: TSymbolLocation): Boolean;
    function DeclarationText(const ALocation: TSymbolLocation): string;
    /// <summary>Symbole AName aus der geprüften Unit (FileName '') und dem Index.</summary>
    function Members(const AName: string): TArray<TSymbolLocation>;
  public
    /// <summary>AUnit: die geprüfte Unit; ihre Klassen (z. B. die Formularklasse) stehen evtl. nicht im Index.</summary>
    constructor Create(const AContext: TRuleContext; const AUnit: TUnitIndex);
    destructor Destroy; override;
    function IsClassOrDescendant(const AClassName, ABase: string; ADescendants: Boolean): Boolean;
    /// <summary>Wert der nicht gespeicherten Property AName von AClassName; False, wenn er unbekannt ist.</summary>
    function DefaultValue(const AClassName, AName: string; out AValue: string): Boolean;
  end;

{ TPropertyChecker }

constructor TPropertyChecker.Create(const AContext: TRuleContext; const AUnit: TUnitIndex);
begin
  inherited Create;
  FContext := AContext;
  FUnit := AUnit;
  FLines := TDictionary<string, TArray<string>>.Create;
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
begin
  if FLines.TryGetValue(UpperCase(AFileName), Result) then
    Exit;
  Result := nil;
  // '' steht für die geprüfte Unit selbst.
  if AFileName = '' then
    Result := FContext.Text.Replace(#13#10, #10).Split([#10])
  else if Assigned(FContext.ReadFile) and FContext.ReadFile(AFileName, Data) then
  begin
    try
      Text := TEncoding.UTF8.GetString(Data);
    except
      on EEncodingError do
        Text := TEncoding.ANSI.GetString(Data);
    end;
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

function TPropertyChecker.DefaultValue(const AClassName, AName: string; out AValue: string): Boolean;
var
  Name, Declaration, TypeName: string;
  Location, Member: TSymbolLocation;
  Depth: Integer;
  Match: TMatch;
begin
  Result := False;
  AValue := '';
  if Pos('.', AName) > 0 then
    Exit;
  Name := AClassName;
  TypeName := '';
  for Depth := 1 to MaxDepth do
  begin
    if not FindClass(Name, Location) then
      Exit;
    for Member in Members(AName) do
      if (Member.Symbol.Kind = TIndexSymbolKind.Property_) and SameText(Member.Symbol.Container, Name) then
      begin
        Declaration := DeclarationText(Member);
        if ContainsText(Declaration, 'nodefault') then
          Exit(False);
        if TDfmPropertyCheckRule.DeclaredDefault(Declaration, AValue) then
          Exit(True);
        // Typ steht nur in der ersten Deklaration; eine Hochstufung (property X;) erbt ihn.
        Match := TRegEx.Match(Declaration, '\bproperty\s+\w+\s*(?:\[[^\]]*\])?\s*:\s*([\w.]+)', [roIgnoreCase]);
        if Match.Success and (TypeName = '') then
        begin
          TypeName := Match.Groups[1].Value;
          Break;
        end;
      end;
    if TypeName <> '' then
      Break;
    if Length(Location.Symbol.Ancestors) = 0 then
      Exit;
    Name := Location.Symbol.Ancestors[0];
  end;
  // Ohne default speichert die VCL alles außer dem Nullwert des Typs.
  if SameText(TypeName, 'Boolean') then
    AValue := 'False'
  else if MatchText(TypeName, ['Integer', 'Cardinal', 'Byte', 'Word', 'SmallInt', 'ShortInt', 'Int64', 'UInt64',
    'NativeInt', 'NativeUInt', 'LongInt', 'LongWord', 'TColor']) then
    AValue := '0'
  else if MatchText(TypeName, ['string', 'UnicodeString', 'WideString', 'AnsiString', 'TCaption']) then
    AValue := ''
  else
    Exit(False);
  Result := True;
end;

{ TDfmPropertyCheckRule }

function TDfmPropertyCheckRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('dfm-property', TRuleSeverity.Warning,
    'Komponenten-Property weicht von einer Eigenschaftsregel aus argus.json ab');
end;

class function TDfmPropertyCheckRule.DeclaredDefault(const ADeclaration: string; out AValue: string): Boolean;
var
  Match: TMatch;
begin
  Match := TRegEx.Match(ADeclaration, '\bdefault\s+([^;]+?)\s*;', [roIgnoreCase]);
  Result := Match.Success;
  if Result then
    AValue := Trim(Match.Groups[1].Value)
  else
    AValue := '';
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

procedure TDfmPropertyCheckRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Model: TFormModel;
  Checker: TPropertyChecker;
  Objects: TArray<TDfmObject>;
  Obj: TDfmObject;
  Rule: TDfmPropertyRule;
  Prop: TDfmProperty;
  Stored: Boolean;
  Actual, Message: string;
  UnitIndex: TUnitIndex;
  Symbol: TIndexSymbol;
  ClassRange, Range: TTextRange;
begin
  if (Length(AContext.DfmPropertyRules) = 0) or (AContext.FormText = '') or (AContext.Tree = nil) then
    Exit;
  // Gemeldet wird in der Unit: am Feld der Komponente, sonst an der Formularklasse.
  UnitIndex := TIndexExtractor.Extract(AContext.Tree, '');
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
        for Prop in Obj.Properties do
          if SameText(Prop.Name, Rule.PropertyPath) then
          begin
            Stored := True;
            Actual := Trim(Prop.Value);
            Break;
          end;
        // Aus dem Vorfahrenformular und hier nicht gesetzt: Sache des Vorfahren.
        if not Stored and (Obj.Kind = TDfmObjectKind.Inherited_) then
          Continue;
        if not Stored and not Checker.DefaultValue(Obj.TypeName, Rule.PropertyPath, Actual) then
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
        AReport.AddWithSeverity(Range, Message, Rule.Severity, nil);
      end;
    end;
  finally
    Checker.Free;
    Model.Free;
  end;
end;

procedure RegisterDfmPropertyRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TDfmPropertyCheckRule.Create);
end;

end.
