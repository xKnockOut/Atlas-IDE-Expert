unit Atlas.Common.Lsp.DebugDisplay;

// Befehl atlas.server.debugDisplayRules (#854): eigene Wertdarstellungen beim
// Debuggen für das IDE-Plugin.
// Argumente: [uri, external]
//   - uri: Projekt (.dproj, .dpr, .dpk), Ordner oder null (einziger
//     Arbeitsbereich); welche Dateien dazugehören, bestimmt das Projektmodell
//     wie bei atlas.server.todos.
//   - external (freiwillig): Typnamen mit Regel aus der Projektdatei .atlas
//     (fremde Klassen wie TFDConnection), damit deren Nachfahren im Projekt
//     die Regel erben.
// Antwort: {"format": 1,
//   "rules": [{"type": "Kunden.TKunde", "name": "TKunde", "template": "…",
//              "children": ["Name", "Ort"], "origin": "comment"|"attribute",
//              "file": "…", "line": 12}],
//   "inherits": [{"type": "Kunden.TGeschaeftskunde", "name": "TGeschaeftskunde",
//                 "from": "Kunden.TKunde" bzw. der Name aus external}]}
// Regeln stehen direkt über der Typdeklaration (Atlas.Text.DebugDisplay); der
// Index liefert die Typen samt Zeile, gelesen werden nur Dateien, deren Text
// atlas-debug oder AtlasDebug enthält. Eine Klasse ohne eigene Regel erbt die
// ihres nächsten Vorfahren mit Regel (über den Index, auch über Units
// außerhalb des Projekts).

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Text.DebugDisplay,
  Atlas.Common.Index.Contract,
  Atlas.Common.Metrics.Collector,
  Atlas.Common.Lsp.Metrics;

type
  TLspDebugDisplayRule = record
    /// <summary>Unit.Typ, bei verschachtelten Typen Unit.TAussen.TInnen.</summary>
    TypeName: string;
    /// <summary>Typ ohne Unit (TAussen.TInnen).</summary>
    Name: string;
    FileName: string;
    Source: TDebugDisplaySource;
  end;

  TLspDebugDisplayInherit = record
    TypeName: string;
    Name: string;
    /// <summary>TypeName der Regel bzw. Name aus external.</summary>
    From: string;
  end;

  TLspDebugDisplay = class
  public const
    Command = 'atlas.server.debugDisplayRules';
    MaxDepth = 32;
  private
    FSourceFor: TLspMetricsSourceFunc;
    FReadText: TMetricsReadText;
    FIndex: ISymbolIndex;
  public
    constructor Create(const ASourceFor: TLspMetricsSourceFunc; const AReadText: TMetricsReadText);
    /// <summary>Führt den Befehl aus; der Aufrufer übernimmt das Ergebnis.</summary>
    function Execute(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Regeln und Erben über die Units AFiles (leer = alle Projekt-Units des Index).</summary>
    function Collect(const AFiles, AExternal: TArray<string>; out AInherits: TArray<TLspDebugDisplayInherit>):
      TArray<TLspDebugDisplayRule>;
    /// <summary>Regeln einer Unit aus ihrem Indexstand und Text.</summary>
    class function RulesOfUnit(const AUnit: TUnitIndex; const AText: string): TArray<TLspDebugDisplayRule>; static;
    /// <summary>Klassen aus AUnits ohne eigene Regel, deren nächster Vorfahr mit Regel in ARules bzw. AExternal
    /// steht.</summary>
    class function InheritsOf(const AIndex: ISymbolIndex; const AUnits: TArray<TUnitIndex>;
      const ARules: TArray<TLspDebugDisplayRule>; const AExternal: TArray<string>): TArray<TLspDebugDisplayInherit>;
      static;
    /// <summary>Lohnt sich das Lesen? Nur Texte mit atlas-debug oder AtlasDebug.</summary>
    class function MayContainRules(const AText: string): Boolean; static;
    /// <summary>Letzter Namensteil ohne Typargumente: Kunden.TKunde → TKunde, TList&lt;T&gt; → TList.</summary>
    class function ShortName(const ATypeName: string): string; static;
    class function ToJson(const ARules: TArray<TLspDebugDisplayRule>;
      const AInherits: TArray<TLspDebugDisplayInherit>): string; static;
    /// <summary>Symbolindex für Typen und Vorfahren; ohne Index gibt es keine Regeln.</summary>
    property Index: ISymbolIndex read FIndex write FIndex;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Uris;

const
  RuleKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType];
  ClassKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType];
  OriginNames: array[TDebugDisplayOrigin] of string = ('comment', 'attribute', 'project');

{ TLspDebugDisplay }

constructor TLspDebugDisplay.Create(const ASourceFor: TLspMetricsSourceFunc; const AReadText: TMetricsReadText);
begin
  inherited Create;
  FSourceFor := ASourceFor;
  FReadText := AReadText;
end;

class function TLspDebugDisplay.MayContainRules(const AText: string): Boolean;
begin
  Result := ContainsText(AText, 'atlas-debug') or ContainsText(AText, 'AtlasDebug');
end;

class function TLspDebugDisplay.ShortName(const ATypeName: string): string;
var
  Angle, Dot: Integer;
begin
  Result := Trim(ATypeName);
  Angle := Pos('<', Result);
  if Angle > 0 then
  begin
    Result := Copy(Result, 1, Angle - 1);
  end;
  Dot := LastDelimiter('.', Result);
  if Dot > 0 then
  begin
    Result := Copy(Result, Dot + 1, MaxInt);
  end;
end;

class function TLspDebugDisplay.RulesOfUnit(const AUnit: TUnitIndex;
  const AText: string): TArray<TLspDebugDisplayRule>;
var
  Lines: TArray<string>;
  Symbol: TIndexSymbol;
  Rule: TLspDebugDisplayRule;
begin
  Result := nil;
  if not MayContainRules(AText) then
  begin
    Exit;
  end;
  Lines := TTextLines.SplitLines(AText);
  for Symbol in AUnit.Symbols do
  begin
    if not (Symbol.Kind in RuleKinds) or (Symbol.FileName <> '') then
    begin
      Continue;
    end;
    Rule := Default(TLspDebugDisplayRule);
    if not TDebugDisplayText.RuleAbove(Lines, Symbol.Range.StartPos.Line, Rule.Source) then
    begin
      Continue;
    end;
    Rule.Name := Symbol.QualifiedName;
    Rule.TypeName := AUnit.UnitName + '.' + Rule.Name;
    Rule.FileName := AUnit.FileName;
    Result := Result + [Rule];
  end;
end;

/// <summary>Erster Vorfahr einer Klasse als Kurzname; '' ohne.</summary>
function FirstAncestor(const ASymbol: TIndexSymbol): string;
begin
  Result := '';
  if Length(ASymbol.Ancestors) > 0 then
  begin
    Result := TLspDebugDisplay.ShortName(ASymbol.Ancestors[0]);
  end;
end;

/// <summary>Kurzname (klein) → Herkunft der Regel; eigene Regeln vor externen. Der Aufrufer gibt frei.</summary>
function RuleOwners(const ARules: TArray<TLspDebugDisplayRule>;
  const AExternal: TArray<string>): TDictionary<string, string>;
var
  mName: string;
  mRule: TLspDebugDisplayRule;
begin
  Result := TDictionary<string, string>.Create;
  for mName in AExternal do
  begin
    if TLspDebugDisplay.ShortName(mName) <> '' then
    begin
      Result.AddOrSetValue(LowerCase(TLspDebugDisplay.ShortName(mName)), mName);
    end;
  end;
  for mRule in ARules do
  begin
    Result.AddOrSetValue(LowerCase(TLspDebugDisplay.ShortName(mRule.Name)), mRule.TypeName);
  end;
end;

/// <summary>Vorfahr der Klasse AName laut Index; '' ohne Index, ohne Klasse oder ohne Vorfahr.</summary>
function AncestorInIndex(const AIndex: ISymbolIndex; const AName: string): string;
var
  mLocation: TSymbolLocation;
begin
  Result := '';
  if AIndex = nil then
  begin
    Exit;
  end;
  for mLocation in AIndex.FindSymbols(AName) do
  begin
    if mLocation.Symbol.Kind in ClassKinds then
    begin
      Exit(FirstAncestor(mLocation.Symbol));
    end;
  end;
end;

/// <summary>Herkunft der Regel, die ASymbol über seine Vorfahren erbt; '' ohne.</summary>
function InheritedOrigin(const AIndex: ISymbolIndex; AOwners: TDictionary<string, string>;
  const ASymbol: TIndexSymbol): string;
var
  mAncestor: string;
  mDepth: Integer;
begin
  Result := '';
  mAncestor := FirstAncestor(ASymbol);
  mDepth := 0;
  while (mAncestor <> '') and (mDepth < TLspDebugDisplay.MaxDepth) do
  begin
    if AOwners.TryGetValue(LowerCase(mAncestor), Result) then
    begin
      Exit;
    end;
    Inc(mDepth);
    mAncestor := AncestorInIndex(AIndex, mAncestor);
  end;
  Result := '';
end;

class function TLspDebugDisplay.InheritsOf(const AIndex: ISymbolIndex; const AUnits: TArray<TUnitIndex>;
  const ARules: TArray<TLspDebugDisplayRule>; const AExternal: TArray<string>): TArray<TLspDebugDisplayInherit>;
var
  mOwners: TDictionary<string, string>;
  mUnit: TUnitIndex;
  mSymbol: TIndexSymbol;
  mInherit: TLspDebugDisplayInherit;
begin
  Result := nil;
  mOwners := RuleOwners(ARules, AExternal);
  try
    if mOwners.Count = 0 then
    begin
      Exit;
    end;
    for mUnit in AUnits do
    begin
      for mSymbol in mUnit.Symbols do
      begin
        if not (mSymbol.Kind in ClassKinds) or mOwners.ContainsKey(LowerCase(mSymbol.Name)) then
        begin
          Continue;
        end;
        mInherit.From := InheritedOrigin(AIndex, mOwners, mSymbol);
        if mInherit.From = '' then
        begin
          Continue;
        end;
        mInherit.Name := mSymbol.QualifiedName;
        mInherit.TypeName := mUnit.UnitName + '.' + mInherit.Name;
        Result := Result + [mInherit];
      end;
    end;
  finally
    mOwners.Free;
  end;
end;

/// <summary>Units zu AFiles (nur .pas im Index); leer = alle Projekt-Units des Index.</summary>
function UnitsOf(const AIndex: ISymbolIndex; const AFiles: TArray<string>): TArray<TUnitIndex>;
var
  mUnit: TUnitIndex;
  mFileName: string;
begin
  Result := nil;
  if Length(AFiles) = 0 then
  begin
    for mUnit in AIndex.Units do
    begin
      if not mUnit.Library_ then
      begin
        Result := Result + [mUnit];
      end;
    end;
    Exit;
  end;
  for mFileName in AFiles do
  begin
    if SameText(ExtractFileExt(mFileName), '.pas') and AIndex.FindFile(mFileName, mUnit) then
    begin
      Result := Result + [mUnit];
    end;
  end;
end;

function TLspDebugDisplay.Collect(const AFiles, AExternal: TArray<string>;
  out AInherits: TArray<TLspDebugDisplayInherit>): TArray<TLspDebugDisplayRule>;
var
  mUnits: TArray<TUnitIndex>;
  mUnit: TUnitIndex;
  mText: string;
begin
  Result := nil;
  AInherits := nil;
  if FIndex = nil then
  begin
    Exit;
  end;
  mUnits := UnitsOf(FIndex, AFiles);
  for mUnit in mUnits do
  begin
    if Assigned(FReadText) and FReadText(mUnit.FileName, mText) then
    begin
      Result := Result + RulesOfUnit(mUnit, mText);
    end;
  end;
  AInherits := InheritsOf(FIndex, mUnits, Result, AExternal);
end;

class function TLspDebugDisplay.ToJson(const ARules: TArray<TLspDebugDisplayRule>;
  const AInherits: TArray<TLspDebugDisplayInherit>): string;
var
  Root, Item: TJSONObject;
  List, Children: TJSONArray;
  Rule: TLspDebugDisplayRule;
  Inherit: TLspDebugDisplayInherit;
  Name: string;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('format', TJSONNumber.Create(1));
    List := TJSONArray.Create;
    Root.AddPair('rules', List);
    for Rule in ARules do
    begin
      Item := TJSONObject.Create;
      List.AddElement(Item);
      Item.AddPair('type', Rule.TypeName);
      Item.AddPair('name', Rule.Name);
      if Rule.Source.HasTemplate then
      begin
        Item.AddPair('template', Rule.Source.Template);
      end;
      if Rule.Source.Children <> nil then
      begin
        Children := TJSONArray.Create;
        for Name in Rule.Source.Children do
        begin
          Children.Add(Name);
        end;
        Item.AddPair('children', Children);
      end;
      Item.AddPair('origin', OriginNames[Rule.Source.Origin]);
      Item.AddPair('file', Rule.FileName);
      Item.AddPair('line', TJSONNumber.Create(Rule.Source.TemplateLine));
    end;
    List := TJSONArray.Create;
    Root.AddPair('inherits', List);
    for Inherit in AInherits do
    begin
      Item := TJSONObject.Create;
      List.AddElement(Item);
      Item.AddPair('type', Inherit.TypeName);
      Item.AddPair('name', Inherit.Name);
      Item.AddPair('from', Inherit.From);
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function TLspDebugDisplay.Execute(const AArguments: TJSONArray): TJSONValue;
var
  FileName: string;
  Source: TLspMetricsSource;
  Foreign: TArray<string>;
  Item: Integer;
  Rules: TArray<TLspDebugDisplayRule>;
  Inherits: TArray<TLspDebugDisplayInherit>;
begin
  FileName := '';
  Foreign := nil;
  if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
  begin
    FileName := TDocumentUris.ToPath(AArguments.Items[0].Value);
  end;
  if (AArguments <> nil) and (AArguments.Count > 1) and (AArguments.Items[1] is TJSONArray) then
  begin
    for Item := 0 to TJSONArray(AArguments.Items[1]).Count - 1 do
    begin
      if TJSONArray(AArguments.Items[1]).Items[Item] is TJSONString then
      begin
        Foreign := Foreign + [TJSONArray(AArguments.Items[1]).Items[Item].Value];
      end;
    end;
  end;
  if not (Assigned(FSourceFor) and FSourceFor(FileName, True, Source)) then
  begin
    Source := Default(TLspMetricsSource);
  end;
  Rules := Collect(Source.Files, Foreign, Inherits);
  Result := TJSONObject.ParseJSONValue(ToJson(Rules, Inherits));
end;

end.
