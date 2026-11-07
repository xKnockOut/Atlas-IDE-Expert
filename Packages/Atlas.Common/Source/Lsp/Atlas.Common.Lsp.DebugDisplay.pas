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
    cCommand = 'atlas.server.debugDisplayRules';
    cMaxDepth = 32;
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
  cRuleKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType];
  cClassKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType];
  cOriginNames: array[TDebugDisplayOrigin] of string = ('comment', 'attribute', 'project');

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
  mAngle, mDot: Integer;
begin
  Result := Trim(ATypeName);
  mAngle := Pos('<', Result);
  if mAngle > 0 then
  begin
    Result := Copy(Result, 1, mAngle - 1);
  end;
  mDot := LastDelimiter('.', Result);
  if mDot > 0 then
  begin
    Result := Copy(Result, mDot + 1, MaxInt);
  end;
end;

class function TLspDebugDisplay.RulesOfUnit(const AUnit: TUnitIndex;
  const AText: string): TArray<TLspDebugDisplayRule>;
var
  mLines: TArray<string>;
  mSymbol: TIndexSymbol;
  mRule: TLspDebugDisplayRule;
begin
  Result := nil;
  if not MayContainRules(AText) then
  begin
    Exit;
  end;
  mLines := TTextLines.SplitLines(AText);
  for mSymbol in AUnit.Symbols do
  begin
    if not (mSymbol.Kind in cRuleKinds) or (mSymbol.FileName <> '') then
    begin
      Continue;
    end;
    mRule := Default(TLspDebugDisplayRule);
    if not TDebugDisplayText.RuleAbove(mLines, mSymbol.Range.StartPos.Line, mRule.Source) then
    begin
      Continue;
    end;
    mRule.Name := mSymbol.QualifiedName;
    mRule.TypeName := AUnit.UnitName + '.' + mRule.Name;
    mRule.FileName := AUnit.FileName;
    Result := Result + [mRule];
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
    if mLocation.Symbol.Kind in cClassKinds then
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
  while (mAncestor <> '') and (mDepth < TLspDebugDisplay.cMaxDepth) do
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
        if not (mSymbol.Kind in cClassKinds) or mOwners.ContainsKey(LowerCase(mSymbol.Name)) then
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
  mRoot, mItem: TJSONObject;
  mList, mChildren: TJSONArray;
  mRule: TLspDebugDisplayRule;
  mInherit: TLspDebugDisplayInherit;
  mName: string;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('format', TJSONNumber.Create(1));
    mList := TJSONArray.Create;
    mRoot.AddPair('rules', mList);
    for mRule in ARules do
    begin
      mItem := TJSONObject.Create;
      mList.AddElement(mItem);
      mItem.AddPair('type', mRule.TypeName);
      mItem.AddPair('name', mRule.Name);
      if mRule.Source.HasTemplate then
      begin
        mItem.AddPair('template', mRule.Source.Template);
      end;
      if mRule.Source.Children <> nil then
      begin
        mChildren := TJSONArray.Create;
        for mName in mRule.Source.Children do
        begin
          mChildren.Add(mName);
        end;
        mItem.AddPair('children', mChildren);
      end;
      mItem.AddPair('origin', cOriginNames[mRule.Source.Origin]);
      mItem.AddPair('file', mRule.FileName);
      mItem.AddPair('line', TJSONNumber.Create(mRule.Source.TemplateLine));
    end;
    mList := TJSONArray.Create;
    mRoot.AddPair('inherits', mList);
    for mInherit in AInherits do
    begin
      mItem := TJSONObject.Create;
      mList.AddElement(mItem);
      mItem.AddPair('type', mInherit.TypeName);
      mItem.AddPair('name', mInherit.Name);
      mItem.AddPair('from', mInherit.From);
    end;
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

function TLspDebugDisplay.Execute(const AArguments: TJSONArray): TJSONValue;
var
  mFileName: string;
  mSource: TLspMetricsSource;
  mForeign: TArray<string>;
  mItem: Integer;
  mRules: TArray<TLspDebugDisplayRule>;
  mInherits: TArray<TLspDebugDisplayInherit>;
begin
  mFileName := '';
  mForeign := nil;
  if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
  begin
    mFileName := TDocumentUris.ToPath(AArguments.Items[0].Value);
  end;
  if (AArguments <> nil) and (AArguments.Count > 1) and (AArguments.Items[1] is TJSONArray) then
  begin
    for mItem := 0 to TJSONArray(AArguments.Items[1]).Count - 1 do
    begin
      if TJSONArray(AArguments.Items[1]).Items[mItem] is TJSONString then
      begin
        mForeign := mForeign + [TJSONArray(AArguments.Items[1]).Items[mItem].Value];
      end;
    end;
  end;
  if not (Assigned(FSourceFor) and FSourceFor(mFileName, True, mSource)) then
  begin
    mSource := Default(TLspMetricsSource);
  end;
  mRules := Collect(mSource.Files, mForeign, mInherits);
  Result := TJSONObject.ParseJSONValue(ToJson(mRules, mInherits));
end;

end.
