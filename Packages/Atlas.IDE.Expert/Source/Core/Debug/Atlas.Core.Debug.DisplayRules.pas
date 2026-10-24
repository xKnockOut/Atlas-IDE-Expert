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
    ServerFormat = 1;
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
  System.JSON;

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
  Angle, Dot: Integer;
begin
  Result := Trim(ATypeName);
  Angle := Pos('<', Result);
  if Angle > 0 then
    Result := Copy(Result, 1, Angle - 1);
  Dot := LastDelimiter('.', Result);
  if Dot > 0 then
    Result := Copy(Result, Dot + 1, MaxInt);
end;

procedure TAtlasDisplayRules.MapName(const AKey: string; AIndex: Integer);
var
  Existing: Integer;
begin
  if AKey = '' then
    Exit;
  // Quelltext schlägt Projektdatei; sonst gilt die erste Regel des Namens.
  if FByName.TryGetValue(AKey, Existing) and
    ((FRules[Existing].Origin <> TDebugDisplayOrigin.Project) or
    (FRules[AIndex].Origin = TDebugDisplayOrigin.Project)) then
    Exit;
  FByName.AddOrSetValue(AKey, AIndex);
end;

procedure TAtlasDisplayRules.Add(const ARule: TAtlasDisplayRule);
var
  Rule: TAtlasDisplayRule;
  Index: Integer;
begin
  Rule := ARule;
  Rule.TypeName := Trim(Rule.TypeName);
  if Rule.Name = '' then
    Rule.Name := ShortName(Rule.TypeName);
  if (Rule.TypeName = '') or (not Rule.HasTemplate and (Rule.Children = nil)) then
    Exit;
  Index := FRules.Add(Rule);
  MapName(LowerCase(Rule.TypeName), Index);
  MapName(LowerCase(Rule.Name), Index);
  MapName(LowerCase(ShortName(Rule.TypeName)), Index);
end;

procedure TAtlasDisplayRules.AddInherit(const ATypeName, AFrom: string);
var
  Name: string;
begin
  if (Trim(ATypeName) = '') or (Trim(AFrom) = '') then
    Exit;
  for Name in TArray<string>.Create(Trim(ATypeName), ShortName(ATypeName)) do
    if not FInherits.ContainsKey(LowerCase(Name)) or (Name = Trim(ATypeName)) then
    begin
      FInherits.AddOrSetValue(LowerCase(Name), Trim(AFrom));
      FInheritNames.AddOrSetValue(LowerCase(Name), Name);
    end;
end;

function TAtlasDisplayRules.LoadJson(const AJson: string): Boolean;
var
  Root, Item: TJSONValue;
  Rule: TAtlasDisplayRule;
  Children: TJSONValue;
  Child: TJSONValue;
  Text, Origin: string;
  Line: Integer;
begin
  Result := False;
  Root := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Root is TJSONObject) or not TJSONObject(Root).TryGetValue<Integer>('format', Line) or
      (Line <> ServerFormat) then
      Exit;
    if TJSONObject(Root).GetValue('rules') is TJSONArray then
      for Item in TJSONArray(TJSONObject(Root).GetValue('rules')) do
      begin
        if not (Item is TJSONObject) then
          Continue;
        Rule := Default(TAtlasDisplayRule);
        Rule.Line := -1;
        TJSONObject(Item).TryGetValue<string>('type', Rule.TypeName);
        TJSONObject(Item).TryGetValue<string>('name', Rule.Name);
        TJSONObject(Item).TryGetValue<string>('template', Rule.Template);
        TJSONObject(Item).TryGetValue<string>('file', Rule.FileName);
        if TJSONObject(Item).TryGetValue<Integer>('line', Line) then
          Rule.Line := Line;
        Origin := '';
        TJSONObject(Item).TryGetValue<string>('origin', Origin);
        if Origin = 'attribute' then
          Rule.Origin := TDebugDisplayOrigin.Attribute
        else
          Rule.Origin := TDebugDisplayOrigin.Comment;
        Children := TJSONObject(Item).GetValue('children');
        if Children is TJSONArray then
          for Child in TJSONArray(Children) do
            if Child is TJSONString then
            begin
              Text := Trim(Child.Value);
              if Text <> '' then
                Rule.Children := Rule.Children + [Text];
            end;
        Add(Rule);
      end;
    if TJSONObject(Root).GetValue('inherits') is TJSONArray then
      for Item in TJSONArray(TJSONObject(Root).GetValue('inherits')) do
        if Item is TJSONObject then
        begin
          Text := '';
          Origin := '';
          TJSONObject(Item).TryGetValue<string>('type', Text);
          TJSONObject(Item).TryGetValue<string>('from', Origin);
          AddInherit(Text, Origin);
        end;
    Result := True;
  finally
    Root.Free;
  end;
end;

function TAtlasDisplayRules.Lookup(const AName: string; out AIndex: Integer): Boolean;
begin
  Result := FByName.TryGetValue(LowerCase(Trim(AName)), AIndex) or
    FByName.TryGetValue(LowerCase(ShortName(AName)), AIndex);
end;

function TAtlasDisplayRules.Find(const ATypeName: string; out ARule: TAtlasDisplayRule): Boolean;
var
  Index: Integer;
  From: string;
begin
  ARule := Default(TAtlasDisplayRule);
  Result := Lookup(ATypeName, Index);
  if not Result and (FInherits.TryGetValue(LowerCase(Trim(ATypeName)), From) or
    FInherits.TryGetValue(LowerCase(ShortName(ATypeName)), From)) then
    Result := Lookup(From, Index);
  if Result then
    ARule := FRules[Index];
end;

function TAtlasDisplayRules.FindChain(const AChain: array of string; out ARule: TAtlasDisplayRule): Boolean;
var
  Name: string;
begin
  for Name in AChain do
    if (Trim(Name) <> '') and Find(Name, ARule) then
      Exit(True);
  ARule := Default(TAtlasDisplayRule);
  Result := False;
end;

function TAtlasDisplayRules.TypeNames: TArray<string>;
var
  Seen: TDictionary<string, Boolean>;
  Rule: TAtlasDisplayRule;
  Name: string;
  Index: Integer;

  procedure AddName(const AName: string);
  begin
    if (AName <> '') and not Seen.ContainsKey(LowerCase(AName)) then
    begin
      Seen.Add(LowerCase(AName), True);
      Result := Result + [AName];
    end;
  end;

begin
  Result := nil;
  Seen := TDictionary<string, Boolean>.Create;
  try
    for Rule in FRules do
    begin
      AddName(Rule.TypeName);
      AddName(ShortName(Rule.TypeName));
    end;
    for Name in FInherits.Keys do
      if Lookup(FInherits[Name], Index) then
        AddName(FInheritNames[Name]);
  finally
    Seen.Free;
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
  Rule: TAtlasDisplayRule;
begin
  Result := nil;
  for Rule in FRules do
    if Rule.Origin = TDebugDisplayOrigin.Project then
      Result := Result + [Rule.TypeName];
end;

{ TAtlasDisplayRender }

class function TAtlasDisplayRender.ExpressionOf(const AExpression, APlaceholder: string): string;
begin
  if (APlaceholder <> '') and (APlaceholder[1] = '[') then
    Result := '(' + AExpression + ')' + APlaceholder
  else
    Result := '(' + AExpression + ').' + APlaceholder;
end;

class function TAtlasDisplayRender.Missing(const APlaceholder: string): string;
begin
  Result := '{?' + APlaceholder + '}';
end;

class function TAtlasDisplayRender.FormatValue(const AText, AFormat: string): string;
var
  Value: Double;
  Invariant: TFormatSettings;
begin
  Result := AText;
  if AFormat = '' then
    Exit;
  Invariant := TFormatSettings.Invariant;
  if TryStrToFloat(Trim(AText), Value, Invariant) then
    Result := FormatFloat(AFormat, Value);
end;

class function TAtlasDisplayRender.PlaceholderText(const ASegment: TDebugDisplaySegment;
  const AExpression: string; const AOptions: TAtlasDisplayRuleOptions; const AEval: TAtlasVisualizerEval): string;
var
  Evaluation: TAtlasVisualizerEvaluation;
  Value: string;
begin
  Result := Missing(ASegment.Text);
  if not Assigned(AEval) or (ASegment.NeedsCall and not AOptions.AllowCalls) then
    Exit;
  // Ohne allowCalls keine Nebenwirkungen: Ein Getter scheitert und zeigt {?…}.
  Evaluation := TAtlasVisualizerEvaluation.Fields;
  if AOptions.AllowCalls then
    Evaluation := TAtlasVisualizerEvaluation.Calls;
  if not AEval(ExpressionOf(AExpression, ASegment.Text), Evaluation, Value) then
    Exit;
  Result := FormatValue(TAtlasVisualizerFormat.Unquote(Value), ASegment.Format);
end;

class function TAtlasDisplayRender.Render(const ARule: TAtlasDisplayRule; const AExpression: string;
  const AOptions: TAtlasDisplayRuleOptions; const AEval: TAtlasVisualizerEval): string;
var
  Template: TDebugDisplayTemplate;
  Segment: TDebugDisplaySegment;
begin
  Result := '';
  if not ARule.HasTemplate then
    Exit;
  Template := TDebugDisplayTemplate.Parse(ARule.Template);
  if not Template.Valid then
    Exit;
  for Segment in Template.Segments do
    if Segment.Kind = TDebugDisplaySegmentKind.Text then
      Result := Result + Segment.Text
    else
      Result := Result + PlaceholderText(Segment, AExpression, AOptions, AEval);
  Result := TAtlasVisualizerFormat.Shorten(Result, AOptions.MaxLength);
end;

class function TAtlasDisplayRender.View(const ARule: TAtlasDisplayRule; const AExpression, AEvalResult: string;
  const AOptions: TAtlasDisplayRuleOptions; const AEval: TAtlasVisualizerEval): TAtlasVisualizerView;
var
  Fields: TArray<TAtlasDebugField>;
  Field: TAtlasDebugField;
  Name, Value, Raw: string;
  Evaluation: TAtlasVisualizerEvaluation;
  Unlimited: TAtlasDisplayRuleOptions;
begin
  Result := Default(TAtlasVisualizerView);
  Result.Mode := TAtlasVisualizerViewMode.Table;
  Result.Columns := TArray<TAtlasVisualizerColumn>.Create(TAtlasVisualizerColumn.Field,
    TAtlasVisualizerColumn.Value);
  Unlimited := AOptions;
  Unlimited.MaxLength := 0;
  Result.Summary := Render(ARule, AExpression, Unlimited, AEval);
  if Result.Summary = '' then
    Result.Summary := AEvalResult;
  Evaluation := TAtlasVisualizerEvaluation.Fields;
  if AOptions.AllowCalls then
    Evaluation := TAtlasVisualizerEvaluation.Calls;
  for Name in ARule.Children do
  begin
    Value := TAtlasDisplayRender.Missing(Name);
    if Assigned(AEval) and AEval(ExpressionOf(AExpression, Name), Evaluation, Raw) then
      Value := Raw;
    Result.Rows := Result.Rows + [TArray<string>.Create(Name, Value)];
  end;
  // Alle Felder: Feldliste des Debuggers (,r zeigt Objekte mit Feldnamen), sonst der Text der IDE.
  Raw := AEvalResult;
  if Assigned(AEval) and AEval(AExpression + ',r', TAtlasVisualizerEvaluation.Fields, Value) then
    Raw := Value;
  if TAtlasVisualizerFormat.ParseFields(Raw, Fields) then
    for Field in Fields do
      Result.AllRows := Result.AllRows + [TArray<string>.Create(Field.Name, Field.Value)];
  if ARule.Children = nil then
  begin
    Result.Rows := Result.AllRows;
    Result.AllRows := nil;
  end;
end;

end.
