unit Atlas.Core.Tracker.IssueForms;

// Issue-Vorlagen von GitHub für „Issue anlegen …“ (#2137), ohne VCL und Open
// Tools API: Formulare (.github/ISSUE_TEMPLATE/*.yml) und Markdown-Vorlagen
// (*.md mit Kopf) lesen, config.yml (blank_issues_enabled), Vorbelegung aus
// dem Wissen von Atlas, Pflichtprüfung, Beschreibung und Adresse für „Im
// Browser fortsetzen“.
// - Felder: markdown (Hinweistext), input, textarea (mit render), dropdown
//   (auch multiple, default) und checkboxes (je Option required). Titel-Präfix
//   (title), labels, assignees, type und projects der Vorlage werden
//   übernommen.
// - Vorbelegung: Zuordnung Feld-Id → Text mit Platzhaltern {version}, {ide},
//   {code}, {finding} und {log} (issues.github.templateFields, .atlas
//   tracker.templateFields). Ohne zugeordnetes Feld für Code bzw. Befund geht
//   {log} in das erste textarea mit render, sonst in das erste textarea. In
//   einem Feld mit render (Codeblock) stehen Code und Text roh, sonst als
//   Markdown mit Codeblock.
// - Beschreibung wie GitHub sie aus Formularen baut: „### <label>“, Leerzeile,
//   Wert; leere Felder „_No response_“, render als Codeblock, checkboxes als
//   „- [X] …“. So sehen Issues aus der IDE und aus dem Browser gleich aus.
// - Eine Vorlage mit Konstrukten, die der YAML-Leser nicht kennt, bleibt in der
//   Liste (Unsupported) und geht nur im Browser.

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  TAtlasIssueFormKind = (Markdown, Input, Textarea, Dropdown, Checkboxes);
{$SCOPEDENUMS OFF}

  /// <summary>Ein Feld eines Formulars (body).</summary>
  TAtlasIssueFormField = record
    Kind: TAtlasIssueFormKind;
    /// <summary>id; '' ohne (dann keine Vorbelegung über Kennung und kein Wert in der Adresse).</summary>
    Id: string;
    /// <summary>attributes.label.</summary>
    Caption: string;
    Description: string;
    Placeholder: string;
    /// <summary>attributes.value: Vorgabe bei input/textarea, Text bei markdown.</summary>
    Value: string;
    /// <summary>attributes.render (textarea): Sprache des Codeblocks; '' = Markdown.</summary>
    Render: string;
    /// <summary>dropdown und checkboxes: Optionen.</summary>
    Options: TArray<string>;
    /// <summary>checkboxes: Pflicht je Option.</summary>
    OptionRequired: TArray<Boolean>;
    /// <summary>validations.required.</summary>
    Required: Boolean;
    /// <summary>dropdown: mehrere Optionen wählbar.</summary>
    Multiple: Boolean;
    /// <summary>dropdown: attributes.default; -1 ohne.</summary>
    DefaultIndex: Integer;
    class function Create(AKind: TAtlasIssueFormKind): TAtlasIssueFormField; static;
    /// <summary>Feld nimmt eine Eingabe (alles außer markdown).</summary>
    function Editable: Boolean;
  end;

  /// <summary>Eine Vorlage aus .github/ISSUE_TEMPLATE.</summary>
  TAtlasIssueForm = record
    /// <summary>Dateiname ohne Pfad ("1-fehler.yml"); für ?template=.</summary>
    FileName: string;
    /// <summary>name; ohne Namen der Dateiname.</summary>
    Name: string;
    /// <summary>description (Formular) bzw. about (Markdown).</summary>
    About: string;
    /// <summary>title: Vorgabe bzw. Präfix des Titels ("Fehler: ").</summary>
    TitlePrefix: string;
    Labels: TArray<string>;
    Assignees: TArray<string>;
    /// <summary>Projekte „owner/nummer“.</summary>
    Projects: TArray<string>;
    /// <summary>type: Issue-Typ; '' ohne.</summary>
    IssueType: string;
    Fields: TArray<TAtlasIssueFormField>;
    /// <summary>Markdown-Vorlage: Body ist der Text der Beschreibung, Fields bleibt leer.</summary>
    IsMarkdown: Boolean;
    Body: string;
    /// <summary>Text, den Atlas nicht lesen kann: nur „Im Browser fortsetzen“.</summary>
    Unsupported: Boolean;
    class function Empty: TAtlasIssueForm; static;
  end;

  /// <summary>Eingabe zu einem Feld: Text (input, textarea) bzw. gewählte Optionen (dropdown, checkboxes).
  /// </summary>
  TAtlasIssueFormAnswer = record
    Text: string;
    Chosen: TArray<Integer>;
    function Has(AIndex: Integer): Boolean;
  end;

  TAtlasIssueFormAnswers = TArray<TAtlasIssueFormAnswer>;

  /// <summary>Was Atlas zur Vorbelegung weiß.</summary>
  TAtlasIssueFormFacts = record
    /// <summary>Version des Plugins.</summary>
    Version: string;
    /// <summary>"Delphi 13 (64-Bit-IDE)".</summary>
    Ide: string;
    /// <summary>Codeausschnitt ohne Codeblock; '' ohne.</summary>
    Code: string;
    /// <summary>Fundstelle bzw. Befunde als Markdown (Beschreibung von #1268).</summary>
    Finding: string;
  end;

  /// <summary>Feld-Id → Text mit Platzhaltern.</summary>
  TAtlasIssueFormMapping = record
    Id: string;
    Value: string;
    class function Create(const AId, AValue: string): TAtlasIssueFormMapping; static;
  end;

  TAtlasIssueFormMappings = TArray<TAtlasIssueFormMapping>;

  /// <summary>Datei aus dem Vorlagenordner: Name ohne Pfad und Text.</summary>
  TAtlasIssueFormFile = record
    Name: string;
    Text: string;
    class function Create(const AName, AText: string): TAtlasIssueFormFile; static;
  end;

  /// <summary>Was „Im Browser fortsetzen“ mitgibt.</summary>
  TAtlasIssueFormLink = record
    /// <summary>Seite des Repositorys ("https://github.com/owner/repo").</summary>
    Repository: string;
    /// <summary>Dateiname der Vorlage; '' = leeres Issue.</summary>
    Template: string;
    Title: string;
    /// <summary>Beschreibung (ohne Formular); '' = keine.</summary>
    Body: string;
    Labels: TArray<string>;
    Assignees: TArray<string>;
    Projects: TArray<string>;
    /// <summary>Titel des Meilensteins; '' ohne.</summary>
    Milestone: string;
    IssueType: string;
    /// <summary>Werte der Formularfelder nach Id.</summary>
    Fields: TAtlasIssueFormMappings;
    class function Empty: TAtlasIssueFormLink; static;
  end;

  TAtlasIssueForms = class
  public const
    /// <summary>Ordner der Vorlagen im Repository.</summary>
    cFolder = '.github/ISSUE_TEMPLATE';
    cConfigName = 'config.yml';
    cNoResponse = '_No response_';
    /// <summary>Vorgabe von issues.github.templateFields (passt zu den Vorlagen von Atlas).</summary>
    cDefaultMapping = 'version={version}; ide={ide}; log={log}';
    cVersion = '{version}';
    cIde = '{ide}';
    cCode = '{code}';
    cFinding = '{finding}';
    cLog = '{log}';
    /// <summary>Höchstens so viele Zeichen je Wert in der Adresse (Browser und GitHub kappen lange Adressen).
    /// </summary>
    cMaxLinkValue = 1500;
  public
    /// <summary>Vorlage nach Endung (.yml, .yaml, .md), nicht config.yml.</summary>
    class function IsFormFile(const AName: string): Boolean; static;
    class function IsConfigFile(const AName: string): Boolean; static;
    /// <summary>Eine Vorlage lesen; False, wenn AFile keine Vorlage ist (andere Endung, Formular ohne body).
    /// Nicht lesbares YAML gibt True mit Unsupported.</summary>
    class function Parse(const AFile: TAtlasIssueFormFile; out AForm: TAtlasIssueForm): Boolean; static;
    /// <summary>blank_issues_enabled aus config.yml; True ohne Angabe.</summary>
    class function BlankAllowed(const AConfig: string): Boolean; static;
    /// <summary>Alle Vorlagen aus AFiles nach Dateinamen sortiert; ABlankAllowed nach config.yml.</summary>
    class function ReadAll(const AFiles: TArray<TAtlasIssueFormFile>; out ABlankAllowed: Boolean):
      TArray<TAtlasIssueForm>; static;
    /// <summary>Titel mit dem Präfix der Vorlage; steht er schon vorn, bleibt ASuggested.</summary>
    class function TitleOf(const AForm: TAtlasIssueForm; const ASuggested: string): string; static;
    /// <summary>Beschriftungen der Pflichtfelder ohne Wert (bzw. Optionen, die angehakt sein müssen).</summary>
    class function Missing(const AForm: TAtlasIssueForm; const AAnswers: TAtlasIssueFormAnswers): TArray<string>;
      static;
    /// <summary>Beschreibung wie aus dem Browser-Formular; bei einer Markdown-Vorlage ihr Text.</summary>
    class function Body(const AForm: TAtlasIssueForm; const AAnswers: TAtlasIssueFormAnswers): string; static;
    /// <summary>"id=wert; id2=wert2" lesen (auch Zeilen statt ";"); leere Ids fallen weg.</summary>
    class function ParseMapping(const AText: string): TAtlasIssueFormMappings; static;
    /// <summary>AOver ersetzt Einträge gleicher Id in ABase und kommt sonst dazu.</summary>
    class function Merge(const ABase, AOver: TAtlasIssueFormMappings): TAtlasIssueFormMappings; static;
    /// <summary>Platzhalter in ATemplate ersetzen; ARendered: Ziel ist ein Codeblock (render).</summary>
    class function Expand(const ATemplate: string; const AFacts: TAtlasIssueFormFacts; ARendered: Boolean): string;
      static;
    /// <summary>Option zu AValue: gleich (ohne Groß-/Kleinschreibung), sonst die erste, die alle Wörter und Zahlen
    /// von AValue enthält, sonst die erste mit allen Zahlen ("Delphi 13 (64-bit IDE)" → „Delphi 13
    /// (64-Bit-IDE)“, „RAD Studio 13, 64 Bit“); -1 ohne.</summary>
    class function MatchOption(const AOptions: TArray<string>; const AValue: string): Integer; static;
    /// <summary>Eingaben mit Vorgaben der Vorlage und der Vorbelegung aus AMappings und AFacts.</summary>
    class function Prefill(const AForm: TAtlasIssueForm; const AMappings: TAtlasIssueFormMappings;
      const AFacts: TAtlasIssueFormFacts): TAtlasIssueFormAnswers; static;
    /// <summary>Werte der Felder für die Adresse (input, textarea, dropdown; nicht checkboxes).</summary>
    class function LinkFields(const AForm: TAtlasIssueForm; const AAnswers: TAtlasIssueFormAnswers):
      TAtlasIssueFormMappings; static;
    /// <summary>…/issues/new?template=…&amp;title=…; '' ohne Repository.</summary>
    class function BrowserUrl(const ALink: TAtlasIssueFormLink): string; static;
  end;

implementation

uses
  System.Character,
  System.StrUtils,
  System.JSON,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Text.Json,
  Atlas.Text.Uris,
  Atlas.Core.Tracker.Internals.FormYaml;

const
  cKindNames: array[TAtlasIssueFormKind] of string = ('markdown', 'input', 'textarea', 'dropdown', 'checkboxes');
  /// <summary>render-Sprachen, in die der Codeausschnitt statt {log} gehört.</summary>
  cCodeRenders: array[0..3] of string = ('pascal', 'delphi', 'objectpascal', 'pas');

{ TAtlasIssueFormField }

class function TAtlasIssueFormField.Create(AKind: TAtlasIssueFormKind): TAtlasIssueFormField;
begin
  Result := Default(TAtlasIssueFormField);
  Result.Kind := AKind;
  Result.Options := nil;
  Result.OptionRequired := nil;
  Result.DefaultIndex := -1;
end;

function TAtlasIssueFormField.Editable: Boolean;
begin
  Result := Kind <> TAtlasIssueFormKind.Markdown;
end;

{ TAtlasIssueForm }

class function TAtlasIssueForm.Empty: TAtlasIssueForm;
begin
  Result := Default(TAtlasIssueForm);
  Result.Labels := nil;
  Result.Assignees := nil;
  Result.Projects := nil;
  Result.Fields := nil;
end;

{ TAtlasIssueFormAnswer }

function TAtlasIssueFormAnswer.Has(AIndex: Integer): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex in Chosen do
  begin
    if mIndex = AIndex then
    begin
      Exit(True);
    end;
  end;
end;

{ TAtlasIssueFormMapping }

class function TAtlasIssueFormMapping.Create(const AId, AValue: string): TAtlasIssueFormMapping;
begin
  Result.Id := AId;
  Result.Value := AValue;
end;

{ TAtlasIssueFormFile }

class function TAtlasIssueFormFile.Create(const AName, AText: string): TAtlasIssueFormFile;
begin
  Result.Name := AName;
  Result.Text := AText;
end;

{ TAtlasIssueFormLink }

class function TAtlasIssueFormLink.Empty: TAtlasIssueFormLink;
begin
  Result := Default(TAtlasIssueFormLink);
  Result.Labels := nil;
  Result.Assignees := nil;
  Result.Projects := nil;
  Result.Fields := nil;
end;

{ Lesen }

/// <summary>Text eines Werts: Zeichenkette, Zahl oder Wahrheitswert als Text; '' sonst.</summary>
function TextOf(AValue: TJSONValue): string;
begin
  Result := '';
  if AValue is TJSONString then
  begin
    Result := AValue.Value;
  end
  else if AValue is TJSONBool then
  begin
    Result := LowerCase(BoolToStr(TJSONBool(AValue).AsBoolean, True));
  end
  else if AValue is TJSONNumber then
  begin
    Result := AValue.Value;
  end;
end;

/// <summary>Liste von Texten: YAML-Liste oder "a, b" als Text (wie GitHub labels und assignees erlaubt).
/// </summary>
function TextsOf(AObject: TJSONObject; const AName: string): TArray<string>;
var
  mValue, mItem: TJSONValue;
  mPart: string;
begin
  Result := nil;
  mValue := TJsonRead.Value(AObject, AName);
  if mValue is TJSONArray then
  begin
    for mItem in TJSONArray(mValue) do
    begin
      if Trim(TextOf(mItem)) <> '' then
      begin
        Result := Result + [Trim(TextOf(mItem))];
      end;
    end;
  end
  else if mValue is TJSONString then
  begin
    for mPart in mValue.Value.Split([',']) do
    begin
      if Trim(mPart) <> '' then
      begin
        Result := Result + [Trim(mPart)];
      end;
    end;
  end;
end;

function KindOf(const AName: string; out AKind: TAtlasIssueFormKind): Boolean;
var
  mKind: TAtlasIssueFormKind;
begin
  for mKind := Low(TAtlasIssueFormKind) to High(TAtlasIssueFormKind) do
  begin
    if SameText(AName, cKindNames[mKind]) then
    begin
      AKind := mKind;
      Exit(True);
    end;
  end;
  AKind := TAtlasIssueFormKind.Markdown;
  Result := False;
end;

/// <summary>Optionen von checkboxes: Liste von {label, required} bzw. Texten.</summary>
procedure ReadCheckOptions(AOptions: TJSONArray; var AField: TAtlasIssueFormField);
var
  mItem: TJSONValue;
begin
  for mItem in AOptions do
  begin
    if mItem is TJSONObject then
    begin
      AField.Options := AField.Options + [TJsonRead.Text(TJSONObject(mItem), 'label')];
      AField.OptionRequired := AField.OptionRequired + [TJsonRead.Flag(TJSONObject(mItem), 'required')];
    end
    else
    begin
      AField.Options := AField.Options + [TextOf(mItem)];
      AField.OptionRequired := AField.OptionRequired + [False];
    end;
  end;
end;

/// <summary>Attribute eines Felds; False bei unbekannter Art.</summary>
function ReadField(AItem: TJSONObject; out AField: TAtlasIssueFormField): Boolean;
var
  mKind: TAtlasIssueFormKind;
  mAttributes, mValidations: TJSONObject;
  mOptions: TJSONArray;
  mDefault: string;
begin
  Result := KindOf(TJsonRead.Text(AItem, 'type'), mKind);
  AField := TAtlasIssueFormField.Create(mKind);
  if not Result then
  begin
    Exit;
  end;
  AField.Id := TJsonRead.TrimmedText(AItem, 'id');
  mAttributes := TJsonRead.Obj(AItem, 'attributes');
  AField.Caption := TJsonRead.Text(mAttributes, 'label');
  AField.Description := TJsonRead.Text(mAttributes, 'description');
  AField.Placeholder := TJsonRead.Text(mAttributes, 'placeholder');
  AField.Value := TextOf(TJsonRead.Value(mAttributes, 'value'));
  AField.Render := TJsonRead.TrimmedText(mAttributes, 'render');
  AField.Multiple := TJsonRead.Flag(mAttributes, 'multiple');
  mOptions := TJsonRead.Items(mAttributes, 'options');
  if (mOptions <> nil) and (mKind = TAtlasIssueFormKind.Checkboxes) then
  begin
    ReadCheckOptions(mOptions, AField);
  end
  else if mOptions <> nil then
  begin
    AField.Options := TextsOf(mAttributes, 'options');
  end;
  mDefault := TextOf(TJsonRead.Value(mAttributes, 'default'));
  AField.DefaultIndex := StrToIntDef(mDefault, -1);
  if AField.DefaultIndex > High(AField.Options) then
  begin
    AField.DefaultIndex := -1;
  end;
  mValidations := TJsonRead.Obj(AItem, 'validations');
  AField.Required := TJsonRead.Flag(mValidations, 'required');
end;

/// <summary>Kopf (name, about/description, title, labels, assignees, projects, type) aus ARoot.</summary>
procedure ReadHead(ARoot: TJSONObject; var AForm: TAtlasIssueForm);
var
  mType: TJSONValue;
begin
  AForm.Name := TJsonRead.TrimmedText(ARoot, 'name');
  AForm.About := TJsonRead.TrimmedText(ARoot, 'description');
  if AForm.About = '' then
  begin
    AForm.About := TJsonRead.TrimmedText(ARoot, 'about');
  end;
  AForm.TitlePrefix := TextOf(TJsonRead.Value(ARoot, 'title'));
  AForm.Labels := TextsOf(ARoot, 'labels');
  AForm.Assignees := TextsOf(ARoot, 'assignees');
  AForm.Projects := TextsOf(ARoot, 'projects');
  mType := TJsonRead.Value(ARoot, 'type');
  AForm.IssueType := Trim(TextOf(mType));
  if mType is TJSONObject then
  begin
    AForm.IssueType := TJsonRead.TrimmedText(TJSONObject(mType), 'name');
  end;
end;

/// <summary>Formular (YAML) in AForm; False ohne body.</summary>
function ParseYaml(const AText: string; var AForm: TAtlasIssueForm): Boolean;
var
  mRoot: TJSONValue;
  mBody: TJSONArray;
  mItem: TJSONValue;
  mField: TAtlasIssueFormField;
begin
  mRoot := TAtlasFormYaml.Parse(AText);
  try
    if not (mRoot is TJSONObject) then
    begin
      AForm.Unsupported := True;
      Exit(True);
    end;
    ReadHead(TJSONObject(mRoot), AForm);
    mBody := TJsonRead.Items(TJSONObject(mRoot), 'body');
    Result := mBody <> nil;
    if not Result then
    begin
      Exit;
    end;
    for mItem in mBody do
    begin
      // Unbekannte Feldarten kann der Dialog nicht zeigen: nur im Browser.
      if not (mItem is TJSONObject) or not ReadField(TJSONObject(mItem), mField) then
      begin
        AForm.Unsupported := True;
        Continue;
      end;
      AForm.Fields := AForm.Fields + [mField];
    end;
  finally
    mRoot.Free;
  end;
end;

/// <summary>Markdown-Vorlage: Kopf zwischen "---"-Zeilen, danach der Text.</summary>
procedure ParseMarkdown(const AText: string; var AForm: TAtlasIssueForm);
var
  mLines: TArray<string>;
  mIndex, mEnd: Integer;
  mHead: TJSONValue;
begin
  AForm.IsMarkdown := True;
  mLines := StringReplace(AText, #13#10, #10, [rfReplaceAll]).Split([#10]);
  mEnd := -1;
  if (Length(mLines) > 0) and (Trim(mLines[0].Replace(#$FEFF, '')) = '---') then
  begin
    for mIndex := 1 to High(mLines) do
    begin
      if Trim(mLines[mIndex]) = '---' then
      begin
        mEnd := mIndex;
        Break;
      end;
    end;
  end;
  if mEnd < 0 then
  begin
    AForm.Body := Trim(AText);
    Exit;
  end;
  mHead := TAtlasFormYaml.Parse(string.Join(#10, Copy(mLines, 1, mEnd - 1)));
  try
    if mHead is TJSONObject then
    begin
      ReadHead(TJSONObject(mHead), AForm);
    end
    else if mHead = nil then
    begin
      AForm.Unsupported := True;
    end;
  finally
    mHead.Free;
  end;
  AForm.Body := Trim(string.Join(#10, Copy(mLines, mEnd + 1, MaxInt)));
end;

class function TAtlasIssueForms.IsConfigFile(const AName: string): Boolean;
begin
  Result := SameText(AName, cConfigName) or SameText(AName, 'config.yaml');
end;

class function TAtlasIssueForms.IsFormFile(const AName: string): Boolean;
var
  mExt: string;
begin
  mExt := LowerCase(ExtractFileExt(AName));
  Result := ((mExt = '.yml') or (mExt = '.yaml') or (mExt = '.md')) and not IsConfigFile(AName);
end;

class function TAtlasIssueForms.Parse(const AFile: TAtlasIssueFormFile; out AForm: TAtlasIssueForm): Boolean;
begin
  AForm := TAtlasIssueForm.Empty;
  AForm.FileName := AFile.Name;
  Result := IsFormFile(AFile.Name);
  if not Result then
  begin
    Exit;
  end;
  if SameText(ExtractFileExt(AFile.Name), '.md') then
  begin
    ParseMarkdown(AFile.Text, AForm);
  end
  else
  begin
    Result := ParseYaml(AFile.Text, AForm);
  end;
  if AForm.Name = '' then
  begin
    AForm.Name := ChangeFileExt(AFile.Name, '');
  end;
end;

class function TAtlasIssueForms.BlankAllowed(const AConfig: string): Boolean;
var
  mRoot: TJSONValue;
begin
  Result := True;
  mRoot := TAtlasFormYaml.Parse(AConfig);
  try
    if mRoot is TJSONObject then
    begin
      Result := TJsonRead.FlagOr(TJSONObject(mRoot), 'blank_issues_enabled', True);
    end;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasIssueForms.ReadAll(const AFiles: TArray<TAtlasIssueFormFile>;
  out ABlankAllowed: Boolean): TArray<TAtlasIssueForm>;
var
  mFile: TAtlasIssueFormFile;
  mForm: TAtlasIssueForm;
begin
  Result := nil;
  ABlankAllowed := True;
  for mFile in AFiles do
  begin
    if IsConfigFile(mFile.Name) then
    begin
      ABlankAllowed := BlankAllowed(mFile.Text);
    end
    else if Parse(mFile, mForm) then
    begin
      Result := Result + [mForm];
    end;
  end;
  // Wie GitHub nach Dateinamen; Namen sind im Ordner eindeutig.
  TArray.Sort<TAtlasIssueForm>(Result, TComparer<TAtlasIssueForm>.Construct(
    function(const ALeft, ARight: TAtlasIssueForm): Integer
    begin
      Result := CompareText(ALeft.FileName, ARight.FileName);
      if Result = 0 then
      begin
        Result := CompareStr(ALeft.FileName, ARight.FileName);
      end;
    end));
end;

class function TAtlasIssueForms.TitleOf(const AForm: TAtlasIssueForm; const ASuggested: string): string;
var
  mPrefix: string;
begin
  mPrefix := AForm.TitlePrefix;
  if (Trim(mPrefix) = '') or StartsText(Trim(mPrefix), Trim(ASuggested)) then
  begin
    Result := ASuggested;
  end
  else
  begin
    Result := mPrefix + TrimLeft(ASuggested);
  end;
end;

{ Prüfen und Beschreibung }

function AnswerOf(const AAnswers: TAtlasIssueFormAnswers; AIndex: Integer): TAtlasIssueFormAnswer;
begin
  if (AIndex >= 0) and (AIndex <= High(AAnswers)) then
  begin
    Result := AAnswers[AIndex];
  end
  else
  begin
    Result := Default(TAtlasIssueFormAnswer);
    Result.Chosen := nil;
  end;
end;

/// <summary>Fehlende Pflichtangaben eines Felds an AMissing anhängen.</summary>
procedure AddMissing(const AField: TAtlasIssueFormField; const AAnswer: TAtlasIssueFormAnswer;
  var AMissing: TArray<string>);
var
  mIndex: Integer;
begin
  case AField.Kind of
    TAtlasIssueFormKind.Input, TAtlasIssueFormKind.Textarea:
      begin
        if AField.Required and (Trim(AAnswer.Text) = '') then
        begin
          AMissing := AMissing + [AField.Caption];
        end;
      end;
    TAtlasIssueFormKind.Dropdown:
      begin
        if AField.Required and (Length(AAnswer.Chosen) = 0) then
        begin
          AMissing := AMissing + [AField.Caption];
        end;
      end;
    TAtlasIssueFormKind.Checkboxes:
      begin
        for mIndex := 0 to High(AField.Options) do
        begin
          if (mIndex <= High(AField.OptionRequired)) and AField.OptionRequired[mIndex] and
            not AAnswer.Has(mIndex) then
          begin
            AMissing := AMissing + [AField.Options[mIndex]];
          end;
        end;
      end;
    TAtlasIssueFormKind.Markdown:
      // Hinweistext ohne Eingabe: nichts zu prüfen.
      Exit;
  end;
end;

class function TAtlasIssueForms.Missing(const AForm: TAtlasIssueForm;
  const AAnswers: TAtlasIssueFormAnswers): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(AForm.Fields) do
  begin
    AddMissing(AForm.Fields[mIndex], AnswerOf(AAnswers, mIndex), Result);
  end;
end;

/// <summary>Zeilenenden auf #10.</summary>
function Unified(const AText: string): string;
begin
  Result := StringReplace(StringReplace(AText, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]);
end;

/// <summary>Gewählte Optionen in der Reihenfolge der Vorlage, durch ", " getrennt.</summary>
function ChosenText(const AField: TAtlasIssueFormField; const AAnswer: TAtlasIssueFormAnswer): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(AField.Options) do
  begin
    if AAnswer.Has(mIndex) then
    begin
      if Result <> '' then
      begin
        Result := Result + ', ';
      end;
      Result := Result + AField.Options[mIndex];
    end;
  end;
end;

/// <summary>Wert eines Felds in der Beschreibung (ohne Überschrift).</summary>
function FieldText(const AField: TAtlasIssueFormField; const AAnswer: TAtlasIssueFormAnswer): string;
var
  mIndex: Integer;
  mMark: string;
begin
  case AField.Kind of
    TAtlasIssueFormKind.Dropdown:
      Result := ChosenText(AField, AAnswer);
    TAtlasIssueFormKind.Checkboxes:
      begin
        Result := '';
        for mIndex := 0 to High(AField.Options) do
        begin
          mMark := ' ';
          if AAnswer.Has(mIndex) then
          begin
            mMark := 'X';
          end;
          if Result <> '' then
          begin
            Result := Result + #10;
          end;
          Result := Result + '- [' + mMark + '] ' + AField.Options[mIndex];
        end;
      end;
  else
    Result := Unified(AAnswer.Text);
    if (Trim(Result) <> '') and (AField.Render <> '') then
    begin
      Result := '```' + AField.Render + #10 + TrimRight(Result) + #10 + '```';
    end;
  end;
  if Trim(Result) = '' then
  begin
    Result := TAtlasIssueForms.cNoResponse;
  end;
end;

class function TAtlasIssueForms.Body(const AForm: TAtlasIssueForm; const AAnswers: TAtlasIssueFormAnswers): string;
var
  mIndex: Integer;
  mParts: TArray<string>;
begin
  if AForm.IsMarkdown then
  begin
    Exit(AForm.Body);
  end;
  mParts := nil;
  for mIndex := 0 to High(AForm.Fields) do
  begin
    if AForm.Fields[mIndex].Editable then
    begin
      mParts := mParts + ['### ' + AForm.Fields[mIndex].Caption + #10#10 +
        FieldText(AForm.Fields[mIndex], AnswerOf(AAnswers, mIndex))];
    end;
  end;
  Result := string.Join(#10#10, mParts);
end;

{ Vorbelegung }

class function TAtlasIssueForms.ParseMapping(const AText: string): TAtlasIssueFormMappings;
var
  mPart, mId: string;
  mEqual: Integer;
begin
  Result := nil;
  for mPart in Unified(AText).Split([';', #10]) do
  begin
    mEqual := Pos('=', mPart);
    if mEqual = 0 then
    begin
      Continue;
    end;
    mId := Trim(Copy(mPart, 1, mEqual - 1));
    if mId <> '' then
    begin
      // "\n" im Wert = Zeilenumbruch, damit mehrere Platzhalter untereinander stehen können.
      Result := Merge(Result, [TAtlasIssueFormMapping.Create(mId,
        StringReplace(Trim(Copy(mPart, mEqual + 1, MaxInt)), '\n', #10, [rfReplaceAll]))]);
    end;
  end;
end;

class function TAtlasIssueForms.Merge(const ABase, AOver: TAtlasIssueFormMappings): TAtlasIssueFormMappings;
var
  mItem: TAtlasIssueFormMapping;
  mIndex: Integer;
  mFound: Boolean;
begin
  Result := Copy(ABase);
  for mItem in AOver do
  begin
    mFound := False;
    for mIndex := 0 to High(Result) do
    begin
      if SameText(Result[mIndex].Id, mItem.Id) then
      begin
        Result[mIndex] := mItem;
        mFound := True;
        Break;
      end;
    end;
    if not mFound then
    begin
      Result := Result + [mItem];
    end;
  end;
end;

/// <summary>Codeblock "pascal" um ACode; enthält ACode selbst ```, dann mit ~~~.</summary>
function Fenced(const ACode: string): string;
var
  mFence: string;
begin
  mFence := '```';
  if ACode.Contains('```') then
  begin
    mFence := '~~~';
  end;
  Result := mFence + 'pascal' + #10 + TrimRight(Unified(ACode)) + #10 + mFence;
end;

/// <summary>Befund und Code: roh (für einen Codeblock) bzw. als Markdown.</summary>
function LogOf(const AFacts: TAtlasIssueFormFacts; ARendered: Boolean): string;
var
  mParts: TArray<string>;
begin
  mParts := nil;
  if Trim(AFacts.Finding) <> '' then
  begin
    mParts := mParts + [Trim(Unified(AFacts.Finding))];
  end;
  if (Trim(AFacts.Code) <> '') and ARendered then
  begin
    mParts := mParts + [TrimRight(Unified(AFacts.Code))];
  end
  else if Trim(AFacts.Code) <> '' then
  begin
    mParts := mParts + [Fenced(AFacts.Code)];
  end;
  Result := string.Join(#10#10, mParts);
end;

class function TAtlasIssueForms.Expand(const ATemplate: string; const AFacts: TAtlasIssueFormFacts;
  ARendered: Boolean): string;
var
  mCode: string;
begin
  mCode := TrimRight(Unified(AFacts.Code));
  if not ARendered and (mCode <> '') then
  begin
    mCode := Fenced(mCode);
  end;
  Result := StringReplace(ATemplate, cVersion, AFacts.Version, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, cIde, AFacts.Ide, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, cCode, mCode, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, cFinding, Trim(Unified(AFacts.Finding)), [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, cLog, LogOf(AFacts, ARendered), [rfReplaceAll, rfIgnoreCase]);
  Result := Trim(Result);
end;

/// <summary>Wörter und Zahlen von AText in Kleinbuchstaben (Trenner: alles außer Buchstaben und Ziffern).
/// </summary>
function Words(const AText: string): TArray<string>;
var
  mWord: string;
  mChar: Char;
begin
  Result := nil;
  mWord := '';
  for mChar in LowerCase(AText) + ' ' do
  begin
    if mChar.IsLetterOrDigit then
    begin
      mWord := mWord + mChar;
    end
    else if mWord <> '' then
    begin
      Result := Result + [mWord];
      mWord := '';
    end;
  end;
end;

/// <summary>Nur die Zahlen aus AWords.</summary>
function Numbers(const AWords: TArray<string>): TArray<string>;
var
  mWord: string;
  mValue: Integer;
begin
  Result := nil;
  for mWord in AWords do
  begin
    if TryStrToInt(mWord, mValue) then
    begin
      Result := Result + [mWord];
    end;
  end;
end;

function ContainsAll(const AHaystack, ANeedles: TArray<string>): Boolean;
var
  mNeedle: string;
begin
  for mNeedle in ANeedles do
  begin
    if IndexStr(mNeedle, AHaystack) < 0 then
    begin
      Exit(False);
    end;
  end;
  Result := Length(ANeedles) > 0;
end;

class function TAtlasIssueForms.MatchOption(const AOptions: TArray<string>; const AValue: string): Integer;
var
  mIndex: Integer;
  mWanted: TArray<string>;
begin
  for mIndex := 0 to High(AOptions) do
  begin
    if SameText(Trim(AOptions[mIndex]), Trim(AValue)) then
    begin
      Exit(mIndex);
    end;
  end;
  mWanted := Words(AValue);
  for mIndex := 0 to High(AOptions) do
  begin
    if ContainsAll(Words(AOptions[mIndex]), mWanted) then
    begin
      Exit(mIndex);
    end;
  end;
  mWanted := Numbers(mWanted);
  for mIndex := 0 to High(AOptions) do
  begin
    if ContainsAll(Words(AOptions[mIndex]), mWanted) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function MappingOf(const AMappings: TAtlasIssueFormMappings; const AId: string; out AValue: string): Boolean;
var
  mItem: TAtlasIssueFormMapping;
begin
  AValue := '';
  Result := False;
  if AId = '' then
  begin
    Exit;
  end;
  for mItem in AMappings do
  begin
    if SameText(mItem.Id, AId) then
    begin
      AValue := mItem.Value;
      Exit(True);
    end;
  end;
end;

/// <summary>Die Vorlage nennt ein Feld für Code bzw. Befund.</summary>
function UsesFacts(const AValue: string): Boolean;
begin
  Result := ContainsText(AValue, TAtlasIssueForms.cCode) or ContainsText(AValue, TAtlasIssueForms.cLog) or
    ContainsText(AValue, TAtlasIssueForms.cFinding);
end;

/// <summary>Vorgabe der Vorlage für ein Feld.</summary>
function DefaultAnswer(const AField: TAtlasIssueFormField): TAtlasIssueFormAnswer;
begin
  Result := Default(TAtlasIssueFormAnswer);
  Result.Chosen := nil;
  if AField.Kind in [TAtlasIssueFormKind.Input, TAtlasIssueFormKind.Textarea] then
  begin
    Result.Text := AField.Value;
  end
  else if (AField.Kind = TAtlasIssueFormKind.Dropdown) and (AField.DefaultIndex >= 0) then
  begin
    Result.Chosen := [AField.DefaultIndex];
  end;
end;

/// <summary>Wert aus der Zuordnung in ein Feld; True, wenn das Feld Code bzw. Befund bekommt.</summary>
function ApplyMapping(const AField: TAtlasIssueFormField; const AValue: string; const AFacts: TAtlasIssueFormFacts;
  var AAnswer: TAtlasIssueFormAnswer): Boolean;
var
  mText: string;
  mIndex: Integer;
begin
  mText := TAtlasIssueForms.Expand(AValue, AFacts, AField.Render <> '');
  Result := UsesFacts(AValue) and (mText <> '');
  if mText = '' then
  begin
    Exit;
  end;
  case AField.Kind of
    TAtlasIssueFormKind.Input:
      AAnswer.Text := StringReplace(mText, #10, ' ', [rfReplaceAll]);
    TAtlasIssueFormKind.Textarea:
      AAnswer.Text := mText;
    TAtlasIssueFormKind.Dropdown:
      begin
        mIndex := TAtlasIssueForms.MatchOption(AField.Options, mText);
        if mIndex >= 0 then
        begin
          AAnswer.Chosen := [mIndex];
        end;
      end;
    TAtlasIssueFormKind.Markdown, TAtlasIssueFormKind.Checkboxes:
      // Kein Wert aus der Zuordnung: Hinweistext bzw. Häkchen setzt nur der Benutzer.
      Exit;
  end;
end;

/// <summary>Feld für Code und Befund ohne Zuordnung: erstes textarea mit render, sonst erstes textarea; -1 ohne.
/// </summary>
function FactsField(const AForm: TAtlasIssueForm; const AAnswers: TAtlasIssueFormAnswers): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(AForm.Fields) do
  begin
    if (AForm.Fields[mIndex].Kind = TAtlasIssueFormKind.Textarea) and (Trim(AAnswers[mIndex].Text) = '') then
    begin
      if AForm.Fields[mIndex].Render <> '' then
      begin
        Exit(mIndex);
      end;
      if Result < 0 then
      begin
        Result := mIndex;
      end;
    end;
  end;
end;

class function TAtlasIssueForms.Prefill(const AForm: TAtlasIssueForm; const AMappings: TAtlasIssueFormMappings;
  const AFacts: TAtlasIssueFormFacts): TAtlasIssueFormAnswers;
var
  mIndex: Integer;
  mValue: string;
  mPlaced: Boolean;
  mField: TAtlasIssueFormField;
begin
  SetLength(Result, Length(AForm.Fields));
  mPlaced := False;
  for mIndex := 0 to High(AForm.Fields) do
  begin
    Result[mIndex] := DefaultAnswer(AForm.Fields[mIndex]);
    if MappingOf(AMappings, AForm.Fields[mIndex].Id, mValue) and
      ApplyMapping(AForm.Fields[mIndex], mValue, AFacts, Result[mIndex]) then
    begin
      mPlaced := True;
    end;
  end;
  if mPlaced or (LogOf(AFacts, False) = '') then
  begin
    Exit;
  end;
  mIndex := FactsField(AForm, Result);
  if mIndex < 0 then
  begin
    Exit;
  end;
  mField := AForm.Fields[mIndex];
  if (mField.Render <> '') and (IndexText(mField.Render, cCodeRenders) >= 0) and (Trim(AFacts.Code) <> '') then
  begin
    Result[mIndex].Text := TrimRight(Unified(AFacts.Code));
  end
  else
  begin
    Result[mIndex].Text := LogOf(AFacts, mField.Render <> '');
  end;
end;

{ Browser }

class function TAtlasIssueForms.LinkFields(const AForm: TAtlasIssueForm;
  const AAnswers: TAtlasIssueFormAnswers): TAtlasIssueFormMappings;
var
  mIndex: Integer;
  mField: TAtlasIssueFormField;
  mAnswer: TAtlasIssueFormAnswer;
  mText: string;
begin
  Result := nil;
  for mIndex := 0 to High(AForm.Fields) do
  begin
    mField := AForm.Fields[mIndex];
    mAnswer := AnswerOf(AAnswers, mIndex);
    if mField.Id = '' then
    begin
      Continue;
    end;
    case mField.Kind of
      TAtlasIssueFormKind.Input, TAtlasIssueFormKind.Textarea:
        mText := mAnswer.Text;
      TAtlasIssueFormKind.Dropdown:
        mText := ChosenText(mField, mAnswer);
    else
      mText := '';
    end;
    if Trim(mText) <> '' then
    begin
      Result := Result + [TAtlasIssueFormMapping.Create(mField.Id, mText)];
    end;
  end;
end;

/// <summary>"&amp;name=wert" mit Prozentkodierung; '' ohne Wert.</summary>
function Param(const AName, AValue: string): string;
begin
  Result := '';
  if Trim(AValue) <> '' then
  begin
    Result := '&' + TTextUris.PercentEncode(AName) + '=' +
      TTextUris.PercentEncode(Copy(Unified(AValue), 1, TAtlasIssueForms.cMaxLinkValue));
  end;
end;

class function TAtlasIssueForms.BrowserUrl(const ALink: TAtlasIssueFormLink): string;
var
  mQuery: string;
  mField: TAtlasIssueFormMapping;
begin
  Result := '';
  if not ALink.Repository.StartsWith('https://', True) then
  begin
    Exit;
  end;
  mQuery := Param('template', ALink.Template) + Param('title', ALink.Title) + Param('body', ALink.Body) +
    Param('labels', string.Join(',', ALink.Labels)) + Param('assignees', string.Join(',', ALink.Assignees)) +
    Param('projects', string.Join(',', ALink.Projects)) + Param('milestone', ALink.Milestone) +
    Param('type', ALink.IssueType);
  for mField in ALink.Fields do
  begin
    mQuery := mQuery + Param(mField.Id, mField.Value);
  end;
  Result := ALink.Repository.TrimRight(['/']) + '/issues/new';
  if mQuery <> '' then
  begin
    Result := Result + '?' + Copy(mQuery, 2, MaxInt);
  end;
end;

end.
