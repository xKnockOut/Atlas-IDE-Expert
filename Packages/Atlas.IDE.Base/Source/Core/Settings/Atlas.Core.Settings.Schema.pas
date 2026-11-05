unit Atlas.Core.Settings.Schema;

// Einstellungen von atlas.json aus dem JSON-Schema (#227): Seite (x-page),
// Beschreibung, Art des Bedienelements und Standardwert. Objekte mit nur
// einfachen Gliedern (compiler, format, highlight …) werden zu einzelnen
// Feldern "objekt.glied". Was sich nicht als einfaches Feld bearbeiten lässt
// (Regeln, Profile, Listen von Objekten), ist Complex: Der Dialog bearbeitet es
// als JSON-Text, die Regeln als Tabelle aus dem Regelkatalog.
// So erscheint jede neue Einstellung im Schema ohne weiteren Code im Dialog.
// x-control (Bedienelement laut Issue), examples (Vorschläge für Textfelder),
// x-restart (wirkt erst nach Neustart) und x-scope (Ort: "global" =
// settings.json, "project" = atlas.json; ein Glied erbt den Ort seines
// Objekts) werden mitgelesen. Ein Glied mit eigenem x-page steht auf dieser
// Seite (#896: diagnostics.usesCycleLive unter Prüfregeln, die übrigen
// diagnostics.* unter Robustheit).

interface

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON;

type
{$SCOPEDENUMS ON}
  TAtlasSettingKind = (Boolean_, Integer_, Text, Choice, List, Complex);
{$SCOPEDENUMS OFF}

  TAtlasSettingField = record
    /// <summary>Pfad in atlas.json, z. B. "compiler.onSave".</summary>
    Path: string;
    Page: string;
    Description: string;
    /// <summary>x-description-en (#1458): englische Beschreibung; leer, wenn das Schema keine hat.</summary>
    DescriptionEn: string;
    Kind: TAtlasSettingKind;
    /// <summary>Bei Choice: erlaubte Werte als JSON-Text ("\"de\"", "true").</summary>
    Choices: TArray<string>;
    /// <summary>Standardwert als JSON-Text; '' ohne Angabe.</summary>
    DefaultJson: string;
    /// <summary>x-control: gewünschtes Bedienelement, z. B. "Datei wählen", "Auswahl aus der .dproj".</summary>
    Control: string;
    /// <summary>examples als Anzeigetexte (Strings ohne Anführungszeichen).</summary>
    Examples: TArray<string>;
    /// <summary>x-restart: Die Änderung wirkt erst nach einem Neustart des Servers.</summary>
    Restart: Boolean;
    /// <summary>x-scope: True = gilt für alle Projekte (settings.json), False = atlas.json des Projekts.</summary>
    Global: Boolean;
    /// <summary>x-scope "both": an beiden Orten, das Projekt übersteuert je Glied (rules).</summary>
    Both: Boolean;
    /// <summary>x-experimental (#834): experimentelle Funktion, wirkt nur mit experimental.enabled.</summary>
    Experimental: Boolean;
    /// <summary>x-control verlangt eine Dateiauswahl.</summary>
    function PicksFile: Boolean;
    /// <summary>Beschreibung in der Sprache der IDE (#1458); ohne englischen Text die deutsche.</summary>
    function DescriptionFor(AEnglish: Boolean): string;
    /// <summary>Passt AJson (JSON-Text) zur Art des Felds? Sonst bleibt der Wert unangetastet.</summary>
    function Accepts(const AJson: string): Boolean;
  end;

  TAtlasSettingsSchema = class
  public
    /// <summary>Felder in der Reihenfolge des Schemas; leer bei ungültigem Schema.</summary>
    class function Fields(const ASchemaJson: string): TArray<TAtlasSettingField>; static;
    /// <summary>Felder eines Orts: AGlobal = settings.json, sonst atlas.json; ohne die Pfade in AExclude und ohne
    /// zusammengesetzte Felder, die einen davon enthalten (z. B. "vcs" mit "vcs.provider").</summary>
    class function ForScope(const AFields: TArray<TAtlasSettingField>; AGlobal: Boolean;
      const AExclude: TArray<string>): TArray<TAtlasSettingField>; static;
    /// <summary>Seiten in der Reihenfolge ihres ersten Felds.</summary>
    class function Pages(const AFields: TArray<TAtlasSettingField>): TArray<string>; static;
    /// <summary>JSON-Text für die Anzeige: Strings ohne Anführungszeichen.</summary>
    class function Display(const AJson: string): string; static;
  end;

implementation

uses
  System.StrUtils;

function TypeOf(ASchema: TJSONObject): string;
var
  Value: TJSONValue;
begin
  Value := ASchema.GetValue('type');
  if Value is TJSONString then
  begin
    Result := TJSONString(Value).Value;
  end
  else if Value is TJSONArray then
  begin
    Result := 'mixed';
  end
  else if ASchema.GetValue('oneOf') <> nil then
  begin
    Result := 'oneOf';
  end
  else
  begin
    Result := '';
  end;
end;

function DescriptionOf(ASchema: TJSONObject): string;
begin
  Result := ASchema.GetValue<string>('description', '');
  if Result = '' then
  begin
    Result := ASchema.GetValue<string>('markdownDescription', '');
  end;
end;

function DescriptionEnOf(ASchema: TJSONObject): string;
begin
  Result := ASchema.GetValue<string>('x-description-en', '');
end;

function EnumChoices(AEnum: TJSONArray): TArray<string>;
var
  mValue: TJSONValue;
begin
  Result := nil;
  for mValue in AEnum do
  begin
    Result := Result + [mValue.ToJSON];
  end;
end;

/// <summary>Array mit Einträgen vom Typ "string".</summary>
function HasStringItems(ASchema: TJSONObject): Boolean;
var
  mItems: TJSONValue;
begin
  mItems := ASchema.GetValue('items');
  Result := (mItems is TJSONObject) and (TypeOf(TJSONObject(mItems)) = 'string');
end;

/// <summary>"oneOf" mit einer Variante vom Typ "string".</summary>
function HasStringOption(ASchema: TJSONObject): Boolean;
var
  mOneOf, mOption: TJSONValue;
begin
  Result := False;
  mOneOf := ASchema.GetValue('oneOf');
  if not (mOneOf is TJSONArray) then
  begin
    Exit;
  end;
  for mOption in TJSONArray(mOneOf) do
  begin
    if (mOption is TJSONObject) and (TypeOf(TJSONObject(mOption)) = 'string') then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Art eines Schemas; Complex, wenn kein einfaches Bedienelement passt.</summary>
function KindOf(ASchema: TJSONObject; out AChoices: TArray<string>): TAtlasSettingKind;
var
  mEnum: TJSONValue;
  mKind: string;
begin
  AChoices := nil;
  mEnum := ASchema.GetValue('enum');
  mKind := TypeOf(ASchema);
  if mEnum is TJSONArray then
  begin
    AChoices := EnumChoices(TJSONArray(mEnum));
    Result := TAtlasSettingKind.Choice;
  end
  else if mKind = 'boolean' then
  begin
    Result := TAtlasSettingKind.Boolean_;
  end
  else if (mKind = 'integer') or (mKind = 'number') then
  begin
    Result := TAtlasSettingKind.Integer_;
  end
  // oneOf mit String-Variante (z. B. profile): als Text, solange der Wert ein String ist.
  else if (mKind = 'string') or ((mKind = 'oneOf') and HasStringOption(ASchema)) then
  begin
    Result := TAtlasSettingKind.Text;
  end
  else if (mKind = 'array') and HasStringItems(ASchema) then
  begin
    Result := TAtlasSettingKind.List;
  end
  else
  begin
    Result := TAtlasSettingKind.Complex;
  end;
end;

/// <summary>Text, aber keine Zahl (TJSONNumber erbt von TJSONString).</summary>
function IsText(AValue: TJSONValue): Boolean;
begin
  Result := (AValue is TJSONString) and not (AValue is TJSONNumber);
end;

/// <summary>Array nur aus Texten.</summary>
function IsTextList(AValue: TJSONValue): Boolean;
var
  mItem: TJSONValue;
begin
  Result := AValue is TJSONArray;
  if not Result then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AValue) do
  begin
    if not IsText(mItem) then
    begin
      Exit(False);
    end;
  end;
end;

function ExamplesOf(AExamples: TJSONValue): TArray<string>;
var
  mExample: TJSONValue;
begin
  Result := nil;
  if not (AExamples is TJSONArray) then
  begin
    Exit;
  end;
  for mExample in TJSONArray(AExamples) do
  begin
    Result := Result + [TAtlasSettingsSchema.Display(mExample.ToJSON)];
  end;
end;

function IsTrueValue(AValue: TJSONValue): Boolean;
begin
  Result := (AValue is TJSONBool) and TJSONBool(AValue).AsBoolean;
end;

function MakeField(const APath, APage: string; ASchema: TJSONObject; const AFallback, AFallbackEn,
  AScope: string): TAtlasSettingField;
var
  mDefault: TJSONValue;
begin
  Result := Default(TAtlasSettingField);
  Result.Path := APath;
  Result.Page := ASchema.GetValue<string>('x-page', APage);
  Result.Description := DescriptionOf(ASchema);
  if Result.Description = '' then
  begin
    Result.Description := AFallback;
  end;
  Result.DescriptionEn := DescriptionEnOf(ASchema);
  if Result.DescriptionEn = '' then
  begin
    Result.DescriptionEn := AFallbackEn;
  end;
  Result.Kind := KindOf(ASchema, Result.Choices);
  mDefault := ASchema.GetValue('default');
  if mDefault <> nil then
  begin
    Result.DefaultJson := mDefault.ToJSON;
  end;
  Result.Control := ASchema.GetValue<string>('x-control', '');
  Result.Examples := ExamplesOf(ASchema.GetValue('examples'));
  Result.Restart := IsTrueValue(ASchema.GetValue('x-restart'));
  Result.Global := ASchema.GetValue<string>('x-scope', AScope) = 'global';
  Result.Both := ASchema.GetValue<string>('x-scope', AScope) = 'both';
  Result.Experimental := IsTrueValue(ASchema.GetValue('x-experimental'));
end;

/// <summary>Alle Glieder sind Objekte, mindestens eins mit einfachem Bedienelement.</summary>
function HasSimpleChildren(AChildren: TJSONObject): Boolean;
var
  mSub: TJSONPair;
  mChoices: TArray<string>;
begin
  Result := False;
  for mSub in AChildren do
  begin
    if not (mSub.JsonValue is TJSONObject) then
    begin
      Exit(False);
    end;
    if KindOf(TJSONObject(mSub.JsonValue), mChoices) <> TAtlasSettingKind.Complex then
    begin
      Result := True;
    end;
  end;
end;

/// <summary>Objekt mit mindestens einem einfachen Glied: Felder je Glied, komplexe Glieder als eigenes
/// JSON-Feld (mcp.customPrompts darf mcp.globalSettings nicht verdecken). False, wenn AChild als ein Feld
/// gilt.</summary>
function AddChildFields(const AName: string; AChild: TJSONObject; var AFields: TArray<TAtlasSettingField>): Boolean;
var
  mChildren: TJSONValue;
  mSub: TJSONPair;
begin
  mChildren := AChild.GetValue('properties');
  Result := (TypeOf(AChild) = 'object') and (mChildren is TJSONObject) and
    HasSimpleChildren(TJSONObject(mChildren));
  if not Result then
  begin
    Exit;
  end;
  for mSub in TJSONObject(mChildren) do
  begin
    AFields := AFields + [MakeField(AName + '.' + mSub.JsonString.Value, AChild.GetValue<string>('x-page', ''),
      TJSONObject(mSub.JsonValue), DescriptionOf(AChild), DescriptionEnOf(AChild),
      AChild.GetValue<string>('x-scope', ''))];
  end;
end;

{ TAtlasSettingField }

function TAtlasSettingField.Accepts(const AJson: string): Boolean;
var
  mValue: TJSONValue;
begin
  if AJson = '' then
  begin
    Exit(True);
  end;
  mValue := TJSONObject.ParseJSONValue(AJson);
  if mValue = nil then
  begin
    Exit(False);
  end;
  try
    case Kind of
      TAtlasSettingKind.Boolean_:
        Result := mValue is TJSONBool;
      TAtlasSettingKind.Integer_:
        Result := mValue is TJSONNumber;
      TAtlasSettingKind.Text:
        Result := IsText(mValue);
      TAtlasSettingKind.Choice:
        Result := MatchStr(mValue.ToJSON, Choices);
      TAtlasSettingKind.List:
        Result := IsTextList(mValue);
    else
      Result := True;
    end;
  finally
    mValue.Free;
  end;
end;

function TAtlasSettingField.DescriptionFor(AEnglish: Boolean): string;
begin
  Result := '';
  if AEnglish then
  begin
    Result := DescriptionEn;
  end;
  if Result = '' then
  begin
    Result := Description;
  end;
end;

function TAtlasSettingField.PicksFile: Boolean;
begin
  Result := Pos('Datei wählen', Control) > 0; // german-ok: Wert aus x-control des Schemas
end;

{ TAtlasSettingsSchema }

class function TAtlasSettingsSchema.Fields(const ASchemaJson: string): TArray<TAtlasSettingField>;
var
  mRoot, mProperties: TJSONValue;
  mPair: TJSONPair;
  mChild: TJSONObject;
begin
  Result := nil;
  mRoot := TJSONObject.ParseJSONValue(ASchemaJson);
  try
    mProperties := nil;
    if mRoot is TJSONObject then
    begin
      mProperties := TJSONObject(mRoot).GetValue('properties');
    end;
    if not (mProperties is TJSONObject) then
    begin
      Exit;
    end;
    for mPair in TJSONObject(mProperties) do
    begin
      if not (mPair.JsonValue is TJSONObject) or (mPair.JsonString.Value = '$schema') then
      begin
        Continue;
      end;
      mChild := TJSONObject(mPair.JsonValue);
      if not AddChildFields(mPair.JsonString.Value, mChild, Result) then
      begin
        Result := Result + [MakeField(mPair.JsonString.Value, mChild.GetValue<string>('x-page', ''), mChild, '', '',
          '')];
      end;
    end;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasSettingsSchema.ForScope(const AFields: TArray<TAtlasSettingField>; AGlobal: Boolean;
  const AExclude: TArray<string>): TArray<TAtlasSettingField>;
var
  Field: TAtlasSettingField;
  Path: string;
  Excluded: Boolean;
begin
  Result := nil;
  for Field in AFields do
  begin
    if (Field.Global <> AGlobal) and not Field.Both then
    begin
      Continue;
    end;
    Excluded := False;
    for Path in AExclude do
    begin
      // Ein zusammengesetztes Feld (ganzes Objekt als JSON, z. B. "vcs" seit #1285) mit einem ausgeschlossenen
      // Glied fällt mit weg: Es im Dialog als Ganzes zu bearbeiten, überschriebe die Werte der eigenen Seite.
      if SameText(Path, Field.Path) or SameText(Copy(Path, 1, Length(Field.Path) + 1), Field.Path + '.') then
      begin
        Excluded := True;
      end;
    end;
    if not Excluded then
    begin
      Result := Result + [Field];
    end;
  end;
end;

class function TAtlasSettingsSchema.Pages(const AFields: TArray<TAtlasSettingField>): TArray<string>;
var
  Field: TAtlasSettingField;
  Page: string;
  Known: Boolean;
begin
  Result := nil;
  for Field in AFields do
  begin
    Known := False;
    for Page in Result do
    begin
      if SameText(Page, Field.Page) then
      begin
        Known := True;
      end;
    end;
    if not Known then
    begin
      Result := Result + [Field.Page];
    end;
  end;
end;

class function TAtlasSettingsSchema.Display(const AJson: string): string;
var
  Value: TJSONValue;
begin
  Result := AJson;
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    if Value is TJSONString then
    begin
      Result := TJSONString(Value).Value;
    end;
  finally
    Value.Free;
  end;
end;

end.
