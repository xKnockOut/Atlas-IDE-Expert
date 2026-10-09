unit Argus.Common.Rules.Catalog;

// Regelkatalog: einzige Quelle für Name, Kategorie, Beschreibung und Beispiele
// jeder Prüfregel (#145). Grundlage ist Katalog\regelkatalog.json (englisch),
// Übersetzungen liegen als Overlay daneben (regelkatalog.de.json) und
// überschreiben nur Name und Beschreibung. SARIF nutzt immer den englischen
// Katalog, damit Fingerabdrücke in GitHub Code Scanning stabil bleiben.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Argus.Common.Configuration.Contract;

type
  TRuleCategory = (Bug, Vulnerability, CodeSmell, SecurityHotspot);

  /// <summary>Ein Eintrag des Regelkatalogs.</summary>
  TRuleCatalogEntry = record
    Id: string;
    Name: string;
    Category: TRuleCategory;
    DefaultSeverity: TRuleSeverity;
    Description: string;
    /// <summary>Beispiel mit Treffer.</summary>
    Bad: string;
    /// <summary>Korrigiertes Beispiel.</summary>
    Good: string;
  end;

  ERuleCatalog = class(Exception);

  TRuleCatalog = class
  private
    FEntries: TList<TRuleCatalogEntry>;
    procedure ParseBase(const AJson: string);
    procedure ApplyOverlay(const AJson: string);
    function IndexOf(const AId: string): Integer;
  public
    /// <summary>Liest den Katalog; AOverlay darf leer sein. Löst ERuleCatalog bei ungültigem Inhalt aus.</summary>
    constructor Create(const ABase: string; const AOverlay: string = '');
    destructor Destroy; override;
    function TryFind(const AId: string; out AEntry: TRuleCatalogEntry): Boolean;
    function Entries: TArray<TRuleCatalogEntry>;
    /// <summary>Link zur Benutzerdokumentation der Regel.</summary>
    class function HelpUri(const AId: string): string; static;
    class function CategoryName(ACategory: TRuleCategory): string; static;
    class function TryParseCategory(const AText: string; out ACategory: TRuleCategory): Boolean; static;
  end;

const
  RuleDocumentationBaseUri = 'https://github.com/xKnockOut/Argus-IDE-Expert/blob/main/docs/Regeln.md#';

implementation

uses
  System.JSON;

const
  CategoryNames: array[TRuleCategory] of string = ('bug', 'vulnerability', 'code-smell', 'security-hotspot');

function TryParseSeverity(const AText: string; out ASeverity: TRuleSeverity): Boolean;
begin
  Result := True;
  if SameText(AText, 'error') then
    ASeverity := TRuleSeverity.Error
  else if SameText(AText, 'warning') then
    ASeverity := TRuleSeverity.Warning
  else if SameText(AText, 'information') then
    ASeverity := TRuleSeverity.Information
  else if SameText(AText, 'hint') then
    ASeverity := TRuleSeverity.Hint
  else
    Result := False;
end;

function StringOf(AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Value := AObject.GetValue(AName);
  if Value is TJSONString then
    Result := TJSONString(Value).Value
  else
    Result := '';
end;

function RulesOf(ARoot: TJSONValue): TJSONArray;
var
  Value: TJSONValue;
begin
  if not (ARoot is TJSONObject) then
    raise ERuleCatalog.Create('Regelkatalog: Objekt erwartet');
  Value := TJSONObject(ARoot).GetValue('rules');
  if not (Value is TJSONArray) then
    raise ERuleCatalog.Create('Regelkatalog: "rules" fehlt');
  Result := TJSONArray(Value);
end;

{ TRuleCatalog }

constructor TRuleCatalog.Create(const ABase, AOverlay: string);
begin
  inherited Create;
  FEntries := TList<TRuleCatalogEntry>.Create;
  ParseBase(ABase);
  if AOverlay <> '' then
    ApplyOverlay(AOverlay);
end;

destructor TRuleCatalog.Destroy;
begin
  FEntries.Free;
  inherited;
end;

procedure TRuleCatalog.ParseBase(const AJson: string);
var
  Root: TJSONValue;
  Rules: TJSONArray;
  I: Integer;
  Item: TJSONObject;
  Entry: TRuleCatalogEntry;
begin
  Root := TJSONObject.ParseJSONValue(AJson);
  try
    Rules := RulesOf(Root);
    for I := 0 to Rules.Count - 1 do
    begin
      if not (Rules.Items[I] is TJSONObject) then
        raise ERuleCatalog.Create('Regelkatalog: Eintrag ist kein Objekt');
      Item := TJSONObject(Rules.Items[I]);
      Entry := Default(TRuleCatalogEntry);
      Entry.Id := StringOf(Item, 'id');
      if Entry.Id = '' then
        raise ERuleCatalog.Create('Regelkatalog: Eintrag ohne "id"');
      if IndexOf(Entry.Id) >= 0 then
        raise ERuleCatalog.CreateFmt('Regelkatalog: "%s" doppelt', [Entry.Id]);
      Entry.Name := StringOf(Item, 'name');
      Entry.Description := StringOf(Item, 'description');
      Entry.Bad := StringOf(Item, 'bad');
      Entry.Good := StringOf(Item, 'good');
      if not TryParseCategory(StringOf(Item, 'category'), Entry.Category) then
        raise ERuleCatalog.CreateFmt('Regelkatalog: "%s" hat keine gültige Kategorie', [Entry.Id]);
      if not TryParseSeverity(StringOf(Item, 'severity'), Entry.DefaultSeverity) then
        raise ERuleCatalog.CreateFmt('Regelkatalog: "%s" hat keinen gültigen Schweregrad', [Entry.Id]);
      FEntries.Add(Entry);
    end;
  finally
    Root.Free;
  end;
end;

procedure TRuleCatalog.ApplyOverlay(const AJson: string);
var
  Root: TJSONValue;
  Rules: TJSONArray;
  I, Index: Integer;
  Item: TJSONObject;
  Entry: TRuleCatalogEntry;
  Text: string;
begin
  Root := TJSONObject.ParseJSONValue(AJson);
  try
    Rules := RulesOf(Root);
    for I := 0 to Rules.Count - 1 do
    begin
      if not (Rules.Items[I] is TJSONObject) then
        Continue;
      Item := TJSONObject(Rules.Items[I]);
      Index := IndexOf(StringOf(Item, 'id'));
      // Übersetzungen unbekannter Regeln sind harmlos und werden übergangen.
      if Index < 0 then
        Continue;
      Entry := FEntries[Index];
      Text := StringOf(Item, 'name');
      if Text <> '' then
        Entry.Name := Text;
      Text := StringOf(Item, 'description');
      if Text <> '' then
        Entry.Description := Text;
      FEntries[Index] := Entry;
    end;
  finally
    Root.Free;
  end;
end;

function TRuleCatalog.IndexOf(const AId: string): Integer;
var
  I: Integer;
begin
  for I := 0 to FEntries.Count - 1 do
    if SameText(FEntries[I].Id, AId) then
      Exit(I);
  Result := -1;
end;

function TRuleCatalog.TryFind(const AId: string; out AEntry: TRuleCatalogEntry): Boolean;
var
  Index: Integer;
begin
  Index := IndexOf(AId);
  Result := Index >= 0;
  if Result then
    AEntry := FEntries[Index]
  else
    AEntry := Default(TRuleCatalogEntry);
end;

function TRuleCatalog.Entries: TArray<TRuleCatalogEntry>;
begin
  Result := FEntries.ToArray;
end;

class function TRuleCatalog.HelpUri(const AId: string): string;
begin
  Result := RuleDocumentationBaseUri + LowerCase(AId);
end;

class function TRuleCatalog.CategoryName(ACategory: TRuleCategory): string;
begin
  Result := CategoryNames[ACategory];
end;

class function TRuleCatalog.TryParseCategory(const AText: string; out ACategory: TRuleCategory): Boolean;
var
  Category: TRuleCategory;
begin
  for Category := Low(TRuleCategory) to High(TRuleCategory) do
    if SameText(AText, CategoryNames[Category]) then
    begin
      ACategory := Category;
      Exit(True);
    end;
  ACategory := TRuleCategory.Bug;
  Result := False;
end;

end.
