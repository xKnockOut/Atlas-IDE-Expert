unit Atlas.Core.Debug.DisplayRules;

// Eigene Wertdarstellung je Typ beim Debuggen (#854), Teil ohne VCL und Open
// Tools API:
// - Regeln: aus der Antwort von atlas.server.debugDisplayRules (Kommentar
//   // atlas-debug: und Attribut [AtlasDebugDisplay] über der Typdeklaration,
//   dazu die Erben ohne eigene Regel) und aus der Projektdatei .atlas
//   (debugDisplayRules, für fremde Klassen wie TFDConnection). Eine Regel im
//   Quelltext schlägt eine gleichnamige aus der Projektdatei.
// - Suche: zuerst der volle Name (Kunden.TKunde), dann der kurze (TKunde),
//   dann über die Erben des Servers; FindChain nimmt das erste Glied einer
//   Vererbungskette (Typ zuerst), das eine Regel hat.
// - Ersatztext: Jeder Platzhalter wird einzeln als „(Ausdruck).Platzhalter“
//   ausgewertet. Ohne debug.displayRules.allowCalls nur ohne Nebenwirkungen
//   (Felder und Eigenschaften mit direktem Feldzugriff); ein Platzhalter mit
//   Aufruf zeigt dann gleich {?Platzhalter}, ebenso jede gescheiterte
//   Auswertung. Zeichenketten ohne Anführungszeichen, Zahlen mit Format
//   ({Betrag:0.00}) über FormatFloat.
// - Ansicht: Tabelle mit den Unterelementen aus atlas-debug-children, dazu
//   „Alle Felder“ (AllRows) aus der Feldliste des Debuggers.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Text.DebugDisplay,
  Atlas.Core.Debug.Visualizers;

type
  TAtlasDisplayRule = record
    /// <summary>Unit.Typ vom Server bzw. der Name aus der Projektdatei.</summary>
    TypeName: string;
    /// <summary>Typ ohne Unit.</summary>
    Name: string;
    Template: string;
    Children: TArray<string>;
    Origin: TDebugDisplayOrigin;
    FileName: string;
    /// <summary>0-basierte Zeile der Regel; -1 ohne (Projektdatei).</summary>
    Line: Integer;
    function HasTemplate: Boolean;
  end;

  TAtlasDisplayRuleOptions = record
    /// <summary>debug.displayRules.allowCalls: Getter und Funktionsaufrufe auswerten.</summary>
    AllowCalls: Boolean;
    /// <summary>Höchstlänge des Ersatztexts; 0 = ohne Grenze.</summary>
    MaxLength: Integer;
  end;

  TAtlasDisplayRules = class
  public const
    cServerFormat = 1;
  private
    FRules: TList<TAtlasDisplayRule>;
    /// <summary>Name klein (voll und kurz) → Index in FRules.</summary>
    FByName: TDictionary<string, Integer>;
    /// <summary>Erbe klein (voll und kurz) → Herkunft der Regel.</summary>
    FInherits: TDictionary<string, string>;
    /// <summary>Erbe klein → Schreibweise für die Anmeldung beim Debugger.</summary>
    FInheritNames: TDictionary<string, string>;
    function Lookup(const AName: string; out AIndex: Integer): Boolean;
    procedure MapName(const AKey: string; AIndex: Integer);
    /// <summary>Regeln aus "rules" (Array) hinzufügen.</summary>
    procedure AddRules(ARules: TJSONValue);
    /// <summary>Erben aus "inherits" (Array) hinzufügen.</summary>
    procedure AddInherits(AInherits: TJSONValue);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure Add(const ARule: TAtlasDisplayRule);
    procedure AddInherit(const ATypeName, AFrom: string);
    /// <summary>Antwort von atlas.server.debugDisplayRules hinzufügen; False bei falschem Format.</summary>
    function LoadJson(const AJson: string): Boolean;
    function Find(const ATypeName: string; out ARule: TAtlasDisplayRule): Boolean;
    function FindChain(const AChain: array of string; out ARule: TAtlasDisplayRule): Boolean;
    /// <summary>Typnamen für die Anmeldung beim Debugger: Regeln und Erben, voll und kurz, ohne doppelte.</summary>
    function TypeNames: TArray<string>;
    function Rules: TArray<TAtlasDisplayRule>;
    function Count: Integer;
    /// <summary>Namen der Regeln aus der Projektdatei (für die Erben über den Server).</summary>
    function ProjectNames: TArray<string>;
    /// <summary>Letzter Namensteil ohne Typargumente.</summary>
    class function ShortName(const ATypeName: string): string; static;
  end;

  TAtlasDisplayRender = class
  public
    /// <summary>Ausdruck eines Platzhalters: „(Kunde).Name“, „(Liste)[0]“.</summary>
    class function ExpressionOf(const AExpression, APlaceholder: string): string; static;
    /// <summary>Anzeige eines nicht auswertbaren Platzhalters: {?Name}.</summary>
    class function Missing(const APlaceholder: string): string; static;
    /// <summary>Zahl mit Format (FormatFloat); andere Werte und leeres Format unverändert.</summary>
    class function FormatValue(const AText, AFormat: string): string; static;
    /// <summary>Wert eines Platzhalters bzw. {?…}.</summary>
    class function PlaceholderText(const ASegment: TDebugDisplaySegment; const AExpression: string;
      const AOptions: TAtlasDisplayRuleOptions; const AEval: TAtlasVisualizerEval): string; static;
    /// <summary>Ersatztext nach der Vorlage; '' ohne Vorlage oder bei ungültiger Vorlage.</summary>
    class function Render(const ARule: TAtlasDisplayRule; const AExpression: string;
      const AOptions: TAtlasDisplayRuleOptions; const AEval: TAtlasVisualizerEval): string; static;
    /// <summary>Tabelle Feld/Wert: Unterelemente der Regel, AllRows alle Felder.</summary>
    class function View(const ARule: TAtlasDisplayRule; const AExpression, AEvalResult: string;
      const AOptions: TAtlasDisplayRuleOptions; const AEval: TAtlasVisualizerEval): TAtlasVisualizerView; static;
  end;

implementation

uses
  Atlas.Core.Settings.VisualizerKinds;

{ TAtlasDisplayRule }

function TAtlasDisplayRule.HasTemplate: Boolean;
begin
  Result := Template <> '';
end;

{ TAtlasDisplayRules }

constructor TAtlasDisplayRules.Create;
begin
  inherited Create;
  FRules := TList<TAtlasDisplayRule>.Create;
  FByName := TDictionary<string, Integer>.Create;
  FInherits := TDictionary<string, string>.Create;
  FInheritNames := TDictionary<string, string>.Create;
end;

destructor TAtlasDisplayRules.Destroy;
begin
  FInheritNames.Free;
  FInherits.Free;
  FByName.Free;
  FRules.Free;
  inherited Destroy;
end;

procedure TAtlasDisplayRules.Clear;
begin
  FRules.Clear;
  FByName.Clear;
  FInherits.Clear;
  FInheritNames.Clear;
end;

class function TAtlasDisplayRules.ShortName(const ATypeName: string): string;
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

procedure TAtlasDisplayRules.MapName(const AKey: string; AIndex: Integer);
var
  mExisting: Integer;
begin
  if AKey = '' then
  begin
    Exit;
  end;
  // Quelltext schlägt Projektdatei; sonst gilt die erste Regel des Namens.
  if FByName.TryGetValue(AKey, mExisting) and
    ((FRules[mExisting].Origin <> TDebugDisplayOrigin.Project) or
    (FRules[AIndex].Origin = TDebugDisplayOrigin.Project)) then
  begin
    Exit;
  end;
  FByName.AddOrSetValue(AKey, AIndex);
end;

procedure TAtlasDisplayRules.Add(const ARule: TAtlasDisplayRule);
var
  mRule: TAtlasDisplayRule;
  mIndex: Integer;
begin
  mRule := ARule;
  mRule.TypeName := Trim(mRule.TypeName);
  if mRule.Name = '' then
  begin
    mRule.Name := ShortName(mRule.TypeName);
  end;
  if (mRule.TypeName = '') or (not mRule.HasTemplate and (mRule.Children = nil)) then
  begin
    Exit;
  end;
  mIndex := FRules.Add(mRule);
  MapName(LowerCase(mRule.TypeName), mIndex);
  MapName(LowerCase(mRule.Name), mIndex);
  MapName(LowerCase(ShortName(mRule.TypeName)), mIndex);
end;

procedure TAtlasDisplayRules.AddInherit(const ATypeName, AFrom: string);
var
  mName: string;
begin
  if (Trim(ATypeName) = '') or (Trim(AFrom) = '') then
  begin
    Exit;
  end;
  for mName in TArray<string>.Create(Trim(ATypeName), ShortName(ATypeName)) do
  begin
    if not FInherits.ContainsKey(LowerCase(mName)) or (mName = Trim(ATypeName)) then
    begin
      FInherits.AddOrSetValue(LowerCase(mName), Trim(AFrom));
      FInheritNames.AddOrSetValue(LowerCase(mName), mName);
    end;
  end;
end;

/// <summary>Namen aus "children": nur nicht leere Zeichenketten.</summary>
function ChildrenOf(AChildren: TJSONValue): TArray<string>;
var
  mChild: TJSONValue;
  mText: string;
begin
  Result := nil;
  if not (AChildren is TJSONArray) then
  begin
    Exit;
  end;
  for mChild in TJSONArray(AChildren) do
  begin
    if mChild is TJSONString then
    begin
      mText := Trim(mChild.Value);
      if mText <> '' then
      begin
        Result := Result + [mText];
      end;
    end;
  end;
end;

/// <summary>Eine Regel aus einem Eintrag von "rules".</summary>
function RuleOf(AItem: TJSONObject): TAtlasDisplayRule;
var
  mLine: Integer;
  mOrigin: string;
begin
  Result := Default(TAtlasDisplayRule);
  Result.Line := -1;
  AItem.TryGetValue<string>('type', Result.TypeName);
  AItem.TryGetValue<string>('name', Result.Name);
  AItem.TryGetValue<string>('template', Result.Template);
  AItem.TryGetValue<string>('file', Result.FileName);
  if AItem.TryGetValue<Integer>('line', mLine) then
  begin
    Result.Line := mLine;
  end;
  mOrigin := '';
  AItem.TryGetValue<string>('origin', mOrigin);
  if mOrigin = 'attribute' then
  begin
    Result.Origin := TDebugDisplayOrigin.Attribute;
  end
  else
  begin
    Result.Origin := TDebugDisplayOrigin.Comment;
  end;
  Result.Children := ChildrenOf(AItem.GetValue('children'));
end;

procedure TAtlasDisplayRules.AddRules(ARules: TJSONValue);
var
  mItem: TJSONValue;
begin
  if not (ARules is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(ARules) do
  begin
    if mItem is TJSONObject then
    begin
      Add(RuleOf(TJSONObject(mItem)));
    end;
  end;
end;

procedure TAtlasDisplayRules.AddInherits(AInherits: TJSONValue);
var
  mItem: TJSONValue;
  mTypeName, mFrom: string;
begin
  if not (AInherits is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AInherits) do
  begin
    if mItem is TJSONObject then
    begin
      mTypeName := '';
      mFrom := '';
      TJSONObject(mItem).TryGetValue<string>('type', mTypeName);
      TJSONObject(mItem).TryGetValue<string>('from', mFrom);
      AddInherit(mTypeName, mFrom);
    end;
  end;
end;

function TAtlasDisplayRules.LoadJson(const AJson: string): Boolean;
var
  mRoot: TJSONValue;
  mVersion: Integer;
begin
  mRoot := TJSONObject.ParseJSONValue(AJson);
  try
    Result := (mRoot is TJSONObject) and TJSONObject(mRoot).TryGetValue<Integer>('format', mVersion) and
      (mVersion = cServerFormat);
    if Result then
    begin
      AddRules(TJSONObject(mRoot).GetValue('rules'));
      AddInherits(TJSONObject(mRoot).GetValue('inherits'));
    end;
  finally
    mRoot.Free;
  end;
end;

function TAtlasDisplayRules.Lookup(const AName: string; out AIndex: Integer): Boolean;
begin
  Result := FByName.TryGetValue(LowerCase(Trim(AName)), AIndex) or
    FByName.TryGetValue(LowerCase(ShortName(AName)), AIndex);
end;

function TAtlasDisplayRules.Find(const ATypeName: string; out ARule: TAtlasDisplayRule): Boolean;
var
  mIndex: Integer;
  mFrom: string;
begin
  ARule := Default(TAtlasDisplayRule);
  Result := Lookup(ATypeName, mIndex);
  if not Result and (FInherits.TryGetValue(LowerCase(Trim(ATypeName)), mFrom) or
    FInherits.TryGetValue(LowerCase(ShortName(ATypeName)), mFrom)) then
  begin
    Result := Lookup(mFrom, mIndex);
  end;
  if Result then
  begin
    ARule := FRules[mIndex];
  end;
end;

function TAtlasDisplayRules.FindChain(const AChain: array of string; out ARule: TAtlasDisplayRule): Boolean;
var
  mName: string;
begin
  for mName in AChain do
  begin
    if (Trim(mName) <> '') and Find(mName, ARule) then
    begin
      Exit(True);
    end;
  end;
  ARule := Default(TAtlasDisplayRule);
  Result := False;
end;

function TAtlasDisplayRules.TypeNames: TArray<string>;
var
  mSeen: TDictionary<string, Boolean>;
  mRule: TAtlasDisplayRule;
  mName: string;
  mIndex: Integer;

  procedure AddName(const AName: string);
  begin
    if (AName <> '') and not mSeen.ContainsKey(LowerCase(AName)) then
    begin
      mSeen.Add(LowerCase(AName), True);
      Result := Result + [AName];
    end;
  end;

begin
  Result := nil;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mRule in FRules do
    begin
      AddName(mRule.TypeName);
      AddName(ShortName(mRule.TypeName));
    end;
    for mName in FInherits.Keys do
    begin
      if Lookup(FInherits[mName], mIndex) then
      begin
        AddName(FInheritNames[mName]);
      end;
    end;
  finally
    mSeen.Free;
  end;
end;

function TAtlasDisplayRules.Rules: TArray<TAtlasDisplayRule>;
begin
  Result := FRules.ToArray;
end;

function TAtlasDisplayRules.Count: Integer;
begin
  Result := FRules.Count;
end;

function TAtlasDisplayRules.ProjectNames: TArray<string>;
var
  mRule: TAtlasDisplayRule;
begin
  Result := nil;
  for mRule in FRules do
  begin
    if mRule.Origin = TDebugDisplayOrigin.Project then
    begin
      Result := Result + [mRule.TypeName];
    end;
  end;
end;

{ TAtlasDisplayRender }

class function TAtlasDisplayRender.ExpressionOf(const AExpression, APlaceholder: string): string;
begin
  if (APlaceholder <> '') and (APlaceholder[1] = '[') then
  begin
    Result := '(' + AExpression + ')' + APlaceholder;
  end
  else
  begin
    Result := '(' + AExpression + ').' + APlaceholder;
  end;
end;

class function TAtlasDisplayRender.Missing(const APlaceholder: string): string;
begin
  Result := '{?' + APlaceholder + '}';
end;

class function TAtlasDisplayRender.FormatValue(const AText, AFormat: string): string;
var
  mValue: Double;
  mInvariant: TFormatSettings;
begin
  Result := AText;
  if AFormat = '' then
  begin
    Exit;
  end;
  mInvariant := TFormatSettings.Invariant;
  if TryStrToFloat(Trim(AText), mValue, mInvariant) then
  begin
    // Anzeige in der IDE: bewusst im Gebietsschema des Benutzers.
    Result := FormatFloat(AFormat, mValue, FormatSettings);
  end;
end;

class function TAtlasDisplayRender.PlaceholderText(const ASegment: TDebugDisplaySegment;
  const AExpression: string; const AOptions: TAtlasDisplayRuleOptions; const AEval: TAtlasVisualizerEval): string;
var
  mEvaluation: TAtlasVisualizerEvaluation;
  mValue: string;
begin
  Result := Missing(ASegment.Text);
  if not Assigned(AEval) or (ASegment.NeedsCall and not AOptions.AllowCalls) then
  begin
    Exit;
  end;
  // Ohne allowCalls keine Nebenwirkungen: Ein Getter scheitert und zeigt {?…}.
  mEvaluation := TAtlasVisualizerEvaluation.Fields;
  if AOptions.AllowCalls then
  begin
    mEvaluation := TAtlasVisualizerEvaluation.Calls;
  end;
  if not AEval(ExpressionOf(AExpression, ASegment.Text), mEvaluation, mValue) then
  begin
    Exit;
  end;
  Result := FormatValue(TAtlasVisualizerFormat.Unquote(mValue), ASegment.Format);
end;

class function TAtlasDisplayRender.Render(const ARule: TAtlasDisplayRule; const AExpression: string;
  const AOptions: TAtlasDisplayRuleOptions; const AEval: TAtlasVisualizerEval): string;
var
  mTemplate: TDebugDisplayTemplate;
  mSegment: TDebugDisplaySegment;
begin
  Result := '';
  if not ARule.HasTemplate then
  begin
    Exit;
  end;
  mTemplate := TDebugDisplayTemplate.Parse(ARule.Template);
  if not mTemplate.Valid then
  begin
    Exit;
  end;
  for mSegment in mTemplate.Segments do
  begin
    if mSegment.Kind = TDebugDisplaySegmentKind.Text then
    begin
      Result := Result + mSegment.Text;
    end
    else
    begin
      Result := Result + PlaceholderText(mSegment, AExpression, AOptions, AEval);
    end;
  end;
  Result := TAtlasVisualizerFormat.Shorten(Result, AOptions.MaxLength);
end;

class function TAtlasDisplayRender.View(const ARule: TAtlasDisplayRule; const AExpression, AEvalResult: string;
  const AOptions: TAtlasDisplayRuleOptions; const AEval: TAtlasVisualizerEval): TAtlasVisualizerView;
var
  mFields: TArray<TAtlasDebugField>;
  mField: TAtlasDebugField;
  mName, mValue, mRaw: string;
  mEvaluation: TAtlasVisualizerEvaluation;
  mUnlimited: TAtlasDisplayRuleOptions;
begin
  Result := Default(TAtlasVisualizerView);
  Result.Mode := TAtlasVisualizerViewMode.Table;
  Result.Columns := TArray<TAtlasVisualizerColumn>.Create(TAtlasVisualizerColumn.Field,
    TAtlasVisualizerColumn.Value);
  mUnlimited := AOptions;
  mUnlimited.MaxLength := 0;
  Result.Summary := Render(ARule, AExpression, mUnlimited, AEval);
  if Result.Summary = '' then
  begin
    Result.Summary := AEvalResult;
  end;
  mEvaluation := TAtlasVisualizerEvaluation.Fields;
  if AOptions.AllowCalls then
  begin
    mEvaluation := TAtlasVisualizerEvaluation.Calls;
  end;
  for mName in ARule.Children do
  begin
    mValue := TAtlasDisplayRender.Missing(mName);
    if Assigned(AEval) and AEval(ExpressionOf(AExpression, mName), mEvaluation, mRaw) then
    begin
      mValue := mRaw;
    end;
    Result.Rows := Result.Rows + [TArray<string>.Create(mName, mValue)];
  end;
  // Alle Felder: Feldliste des Debuggers (,r zeigt Objekte mit Feldnamen), sonst der Text der IDE.
  mRaw := AEvalResult;
  if Assigned(AEval) and AEval(AExpression + ',r', TAtlasVisualizerEvaluation.Fields, mValue) then
  begin
    mRaw := mValue;
  end;
  if TAtlasVisualizerFormat.ParseFields(mRaw, mFields) then
  begin
    for mField in mFields do
    begin
      Result.AllRows := Result.AllRows + [TArray<string>.Create(mField.Name, mField.Value)];
    end;
  end;
  if ARule.Children = nil then
  begin
    Result.Rows := Result.AllRows;
    Result.AllRows := nil;
  end;
end;

end.
