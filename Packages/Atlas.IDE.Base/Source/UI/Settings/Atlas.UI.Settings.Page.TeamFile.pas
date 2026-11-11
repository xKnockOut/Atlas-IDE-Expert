unit Atlas.UI.Settings.Page.TeamFile;

// Reiter „Einfügen“ (Hinweis auf Vorlagen der Projektdatei, #486) und „Projektdatei“ (.atlas).

interface

uses
  System.SysUtils,
  Vcl.StdCtrls,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.TeamFile,
  Atlas.UI.Settings.Page.Host;

type
  /// <summary>Reiter „Einfügen“ (Hinweis auf Vorlagen der Projektdatei, #486) und „Projektdatei“ (.atlas).</summary>
  TAtlasSettingsTeamFilePart = class(TAtlasSettingsPagePart)
  private
    // Projektdatei .atlas (#486): Schalter, Anzeige der Werte „aus .atlas“, Öffnen; Hinweis bei den Vorlagen.
    FTeamFile: TCheckBox;
    FTeamFileInfo: TLabel;
    FTeamFileOpen: TButton;
    FTeamSnippets: TLabel;
    FOnTeamFile: TFunc<TAtlasTeamSettings>;
    FOnOpenTeamFile: TProc;
    procedure AddTeamFileSection;
    procedure TeamFileClick(Sender: TObject);
    procedure TeamFileOpenClick(Sender: TObject);
    procedure SetOnTeamFile(const AValue: TFunc<TAtlasTeamSettings>);
  public
    procedure Build;
    procedure Build2;
    procedure Load(const ASettings: TAtlasPluginSettings); override;
    /// <summary>Anzeige der Projektdatei neu aufbauen (#486).</summary>
    procedure RefreshTeamFile;
    /// <summary>Projektdatei .atlas des aktiven Projekts (#486) für die Anzeige „aus .atlas“; nil = keine.</summary>
    property OnTeamFile: TFunc<TAtlasTeamSettings> read FOnTeamFile write SetOnTeamFile;
    /// <summary>„Projektdatei öffnen“: anlegen, falls es sie nicht gibt, und im Editor öffnen (#486).</summary>
    property OnOpenTeamFile: TProc read FOnOpenTeamFile write FOnOpenTeamFile;
    /// <summary>Zum Testen: Projektdatei (#486).</summary>
    property TeamFileCheck: TCheckBox read FTeamFile;
    property TeamFileInfo: TLabel read FTeamFileInfo;
    property TeamFileOpenButton: TButton read FTeamFileOpen;
    property TeamSnippetsLabel: TLabel read FTeamSnippets;
  end;

implementation

uses
  Vcl.Controls,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Strings;

/// <summary>Fehler einer ungültigen Projektdatei; mit Zeile und Spalte, wenn bekannt: Dort steht er im JSON.
/// </summary>
function TeamInvalidText(const ATeam: TAtlasTeamSettings): string;
var
  mIssue: TAtlasTeamIssue;
begin
  Result := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsTeamFileInvalid);
  for mIssue in ATeam.Issues do
  begin
    if (mIssue.Kind = TAtlasTeamIssueKind.Syntax) and (mIssue.Line > 0) then
    begin
      Exit(TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.SettingsTeamFileInvalidAt, [mIssue.Line, mIssue.Column]));
    end;
  end;
end;

/// <summary>Werte einer gültigen Projektdatei nach der Zeile mit ihrem Ort.</summary>
function TeamValueLines(const ATeam: TAtlasTeamSettings): TArray<string>;
var
  mValue: TAtlasTeamValue;
begin
  Result := nil;
  for mValue in TAtlasTeamFile.Values(ATeam) do
  begin
    Result := Result + [TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.SettingsTeamFileValue, [mValue.Key,
      mValue.Value])];
  end;
  if Length(Result) = 0 then
  begin
    Result := Result + [TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsTeamFileNoValues)];
  end;
  if Length(ATeam.Issues) > 0 then
  begin
    Result := Result + [TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.SettingsTeamFileIssues, [Length(ATeam.Issues)])];
  end;
end;

/// <summary>Zeilen der Anzeige „aus .atlas“ (#486).</summary>
function TeamFileLines(AOn: Boolean; const ATeam: TAtlasTeamSettings): TArray<string>;
begin
  if not AOn then
  begin
    Result := TArray<string>.Create(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsTeamFileOff));
  end
  else if ATeam.Project = '' then
  begin
    Result := TArray<string>.Create(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsTeamFileNoProject));
  end
  else if not ATeam.Exists then
  begin
    Result := TArray<string>.Create(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsTeamFileMissing));
  end
  else if not ATeam.Valid then
  begin
    Result := TArray<string>.Create(TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.SettingsTeamFileLocation,
      [ATeam.FileName]),
      TeamInvalidText(ATeam));
  end
  else
  begin
    Result := TArray<string>.Create(TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.SettingsTeamFileLocation,
      [ATeam.FileName])) +
      TeamValueLines(ATeam);
  end;
end;

{ TAtlasSettingsTeamFilePart }

procedure TAtlasSettingsTeamFilePart.Build;
begin
  // Was beim Übernehmen eingefügt wird.
  AddSheet(TAtlasTextId.SettingsTabInsert);
  BindCheck('AutoParentheses', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsParentheses)));
  BindCheck('FixCase', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsFixCase)));
  BindCheck('CommitCharacters', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsCommitChars)));
  BindCheck('AutoUses', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsAutoUses)));
  BindCheck('ParameterHints', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsParameterHints)));
  BindCheck('FormatPlaceholders',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsFormatPlaceholders)));
  // Code-Vorlagen (#51).
  BindCheck('Snippets', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsSnippets)));
  BindCheck('ImportIdeTemplates',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsImportIdeTemplates)));
  // Vorlagen aus der Projektdatei (#486); leer ohne .atlas.
  FTeamSnippets := AddWrappedLabel(20, '');
end;

procedure TAtlasSettingsTeamFilePart.Build2;
begin
  AddSheet(TAtlasTextId.SettingsTabTeamFile);
  AddTeamFileSection;
end;

procedure TAtlasSettingsTeamFilePart.Load(const ASettings: TAtlasPluginSettings);
begin
  RefreshTeamFile;
end;

procedure TAtlasSettingsTeamFilePart.AddTeamFileSection;
var
  mPanel: TWinControl;
begin
  // Projektdatei .atlas (#486): Schalter, Erklärung, „Projektdatei öffnen“ und jeder Wert mit „aus .atlas“.
  FTeamFile := BindCheck('TeamFile', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsTeamFile)));
  FTeamFile.OnClick := TeamFileClick;
  Attach(AddWrappedLabel(36, TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsTeamFileHint)).Parent, FTeamFile);
  mPanel := AddPanel(32);
  FTeamFileOpen := TButton.Create(FPage);
  FTeamFileOpen.Parent := mPanel;
  FTeamFileOpen.Caption := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsTeamFileOpen);
  FTeamFileOpen.Left := 0;
  FTeamFileOpen.Top := 3;
  FTeamFileOpen.Width := 180;
  FTeamFileOpen.OnClick := TeamFileOpenClick;
  Attach(mPanel, FTeamFile);
  FTeamFileInfo := AddWrappedLabel(180, '');
  Attach(FTeamFileInfo.Parent, FTeamFile);
  RefreshTeamFile;
end;

procedure TAtlasSettingsTeamFilePart.TeamFileClick(Sender: TObject);
begin
  RefreshTeamFile;
end;

procedure TAtlasSettingsTeamFilePart.TeamFileOpenClick(Sender: TObject);
begin
  if Assigned(FOnOpenTeamFile) then
  begin
    FOnOpenTeamFile();
  end;
  RefreshTeamFile;
end;

procedure TAtlasSettingsTeamFilePart.SetOnTeamFile(const AValue: TFunc<TAtlasTeamSettings>);
begin
  FOnTeamFile := AValue;
  RefreshTeamFile;
end;

procedure TAtlasSettingsTeamFilePart.RefreshTeamFile;
var
  mTeam: TAtlasTeamSettings;
begin
  // Ausgeschaltet wird die Datei nicht gelesen.
  mTeam := TAtlasTeamFile.Empty;
  if FTeamFile.Checked and Assigned(FOnTeamFile) then
  begin
    mTeam := FOnTeamFile();
  end;
  FTeamSnippets.Caption := '';
  if mTeam.Valid and (mTeam.Snippets <> '') then
  begin
    FTeamSnippets.Caption := TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.SettingsTeamSnippets, [mTeam.Snippets]);
  end;
  FTeamFileInfo.Caption := string.Join(sLineBreak, TeamFileLines(FTeamFile.Checked, mTeam));
  Allow(FTeamFileOpen, FTeamFile.Checked and (mTeam.Project <> ''));
end;

end.
