unit Atlas.Core.Settings.RuleChecksNotice;

// Hinweis „Prüfregeln sind aus“ (#1454), ohne VCL und ohne IDE: Legt die
// atlas.json eines geöffneten Projekts Prüfregeln fest (Schlüssel rules mit
// mindestens einem Eintrag oder profile), ist das Modul Prüfregeln
// (ruleChecks.enabled) aber aus, weist Atlas einmal je atlas.json und Sitzung
// darauf hin. Die IDE-Seite (TAtlasIdeRuleChecksNotice) meldet geöffnete
// Projekte und zeigt den Hinweis mit „Prüfregeln einschalten“.

interface

uses
  System.SysUtils;

type
  /// <summary>Besteht die Datei AFileName? Für Tests ersetzbar.</summary>
  TAtlasConfigExists = reference to function(const AFileName: string): Boolean;

  TAtlasRuleChecksNotice = class
  public const
    ConfigName = 'atlas.json';
  private
    /// <summary>Dateien, zu denen der Hinweis schon kam (volle Pfade).</summary>
    FShown: TArray<string>;
    function WasShown(const AConfigFile: string): Boolean;
  public
    /// <summary>True, wenn der Text Prüfregeln festlegt: rules als Objekt mit mindestens einem Eintrag oder
    /// profile als nicht leere Zeichenkette. Kommentare sind erlaubt (JSONC); ungültiger Text = False.</summary>
    class function HasRules(const AJsonText: string): Boolean; static;
    /// <summary>Nächste atlas.json über dem Ordner von AProjectFile (der Ordner selbst zuerst, dann aufwärts);
    /// '' ohne. AExists prüft, ob eine Datei besteht.</summary>
    class function ConfigFor(const AProjectFile: string; const AExists: TAtlasConfigExists): string; static;
    /// <summary>True, wenn der Hinweis zu AConfigFile jetzt kommen soll: Modul aus, Regeln im Text und in dieser
    /// Sitzung noch nicht gezeigt. Merkt sich die Datei dann gleich (auch wenn der Hinweis nur gesammelt wird).
    /// </summary>
    function Wanted(const AConfigFile, AJsonText: string; AModuleOn: Boolean): Boolean;
    /// <summary>Gezeigte Dateien vergessen, z. B. nach dem Einschalten des Moduls.</summary>
    procedure Reset;
  end;

implementation

uses
  System.Generics.Collections,
  System.JSON,
  Atlas.Core.Settings.JsonText;

{ TAtlasRuleChecksNotice }

class function TAtlasRuleChecksNotice.HasRules(const AJsonText: string): Boolean;
var
  mRoot: TJSONObject;
  mValue: TJSONValue;
begin
  Result := False;
  mRoot := TAtlasJsonText.Parse(AJsonText);
  if mRoot = nil then
  begin
    Exit;
  end;
  try
    mValue := mRoot.GetValue('rules');
    if (mValue is TJSONObject) and (TJSONObject(mValue).Count > 0) then
    begin
      Exit(True);
    end;
    mValue := mRoot.GetValue('profile');
    Result := (mValue is TJSONString) and (Trim(mValue.Value) <> '');
  finally
    mRoot.Free;
  end;
end;

class function TAtlasRuleChecksNotice.ConfigFor(const AProjectFile: string;
  const AExists: TAtlasConfigExists): string;
var
  mFolder, mParent, mFile: string;
begin
  Result := '';
  if (AProjectFile = '') or not Assigned(AExists) then
  begin
    Exit;
  end;
  mFolder := ExtractFileDir(AProjectFile.Replace('/', PathDelim));
  while mFolder <> '' do
  begin
    mFile := IncludeTrailingPathDelimiter(mFolder) + ConfigName;
    if AExists(mFile) then
    begin
      Exit(mFile);
    end;
    mParent := ExtractFileDir(ExcludeTrailingPathDelimiter(mFolder));
    if SameText(mParent, mFolder) then
    begin
      Exit;
    end;
    mFolder := mParent;
  end;
end;

function TAtlasRuleChecksNotice.WasShown(const AConfigFile: string): Boolean;
var
  mFile: string;
begin
  Result := False;
  for mFile in FShown do
  begin
    if SameText(mFile, AConfigFile) then
    begin
      Exit(True);
    end;
  end;
end;

function TAtlasRuleChecksNotice.Wanted(const AConfigFile, AJsonText: string; AModuleOn: Boolean): Boolean;
begin
  Result := False;
  if AModuleOn or (AConfigFile = '') or WasShown(AConfigFile) or not HasRules(AJsonText) then
  begin
    Exit;
  end;
  FShown := FShown + [AConfigFile];
  Result := True;
end;

procedure TAtlasRuleChecksNotice.Reset;
begin
  FShown := nil;
end;

end.
