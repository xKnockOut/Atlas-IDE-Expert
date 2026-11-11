unit Atlas.UI.Settings.Page.Completion;

// Reiter „Vervollständigung“: Zeilen, Breite, Listenmodus, Verlauf, angeheftete Favoriten (#458) und gelernte
// Vorschläge (#1890).

interface

uses
  System.SysUtils,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Completion.Favorites,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Settings.Page.Host;

type
  /// <summary>Reiter „Vervollständigung“: Zeilen, Breite, Listenmodus, Verlauf und angeheftete Favoriten
  /// (#458).</summary>
  TAtlasSettingsCompletionPart = class(TAtlasSettingsPagePart)
  private
    FRowsLabel: TLabel;
    FRows: TEdit;
    FRowsUpDown: TUpDown;
    FAutoWidth: TCheckBox;
    /// <summary>Listenmodus beim Tippen und sein Geltungsbereich (#497).</summary>
    FListMode: TAtlasChoiceBox;
    FListScope: TAtlasChoiceBox;
    FResetHistory: TButton;
    // Favoriten (#458): Schalter, Liste und Schlüssel je Zeile.
    FFavorites: TCheckBox;
    FResetWidths: TButton;
    /// <summary>Breiten der Vervollständigungsliste (gezogen bzw. zurückgesetzt), gespeichert mit OK.</summary>
    FListWidth, FPanelWidth: Integer;
    FOnResetHistory: TProc;
    procedure ResetHistoryClick(Sender: TObject);
    procedure ResetWidthsClick(Sender: TObject);
    procedure AutoWidthClick(Sender: TObject);
  public
    procedure Build;
    procedure Build2;
    procedure Load(const ASettings: TAtlasPluginSettings); override;
    procedure Save(var ASettings: TAtlasPluginSettings); override;
    procedure BindMarks; override;
    /// <summary>„Verlauf zurücksetzen“ der lernenden Gewichtung (#418).</summary>
    property OnResetHistory: TProc read FOnResetHistory write FOnResetHistory;
    /// <summary>Zum Testen: Favoriten (#458).</summary>
    property FavoritesCheck: TCheckBox read FFavorites;
    /// <summary>Zum Testen: Listenmodus der Vervollständigung (#497).</summary>
    property ListModeChoice: TAtlasChoiceBox read FListMode;
    property ListScopeChoice: TAtlasChoiceBox read FListScope;
    property AutoWidth: TCheckBox read FAutoWidth;
  end;

  /// <summary>Angeheftete Favoriten (#458) auf dem Reiter „Vervollständigung“: Liste mit „Entfernen“ und „Alle
  /// entfernen“. Die Seite kennt die Ablage nicht; OnFavorites liefert die Liste, OnRemoveFavorites löst die
  /// Schlüssel sofort (nicht erst mit OK).</summary>
  TAtlasSettingsFavoritesPart = class(TAtlasSettingsPagePart)
  private
    FFavoritesList: TListBox;
    FFavoritesRemove: TButton;
    FFavoritesRemoveAll: TButton;
    /// <summary>Schlüssel je Zeile der Liste.</summary>
    FFavoriteKeys: TArray<string>;
    FOnFavorites: TFunc<TArray<TAtlasFavorite>>;
    FOnRemoveFavorites: TProc<TArray<string>>;
    procedure FavoritesRemoveClick(Sender: TObject);
    procedure FavoritesRemoveAllClick(Sender: TObject);
    procedure SetOnFavorites(const AValue: TFunc<TArray<TAtlasFavorite>>);
  public
    procedure Build;
    procedure WindowReady; override;
    /// <summary>Liste der angehefteten Favoriten neu lesen (#458).</summary>
    procedure RefreshFavorites;
    /// <summary>Angeheftete Favoriten (#458) für die Liste; nil = keine Liste.</summary>
    property OnFavorites: TFunc<TArray<TAtlasFavorite>> read FOnFavorites write SetOnFavorites;
    /// <summary>Favoriten mit diesen Schlüsseln lösen (#458, „Entfernen“, „Alle entfernen“).</summary>
    property OnRemoveFavorites: TProc<TArray<string>> read FOnRemoveFavorites write FOnRemoveFavorites;
    /// <summary>Zum Testen.</summary>
    property FavoritesList: TListBox read FFavoritesList;
    property FavoritesRemove: TButton read FFavoritesRemove;
    property FavoritesRemoveAll: TButton read FFavoritesRemoveAll;
  end;

implementation

uses
  System.Math,
  Vcl.Controls,
  Atlas.UI.Settings.Page.Sheets,
  Atlas.UI.Strings,
  Atlas.UI.Editor.LearnedSuggestions,
  Atlas.UI.Settings.Strings,
  Atlas.Core.Completion.Ranking;

{ TAtlasSettingsCompletionPart }

procedure TAtlasSettingsCompletionPart.Build;
var
  mPanel: TWinControl;
begin
  // Liste der Vervollständigung.
  AddSheet(TAtlasTextId.SettingsTabCompletion);
  mPanel := AddPanel(26);
  FRowsLabel := TLabel.Create(FPage);
  FRowsLabel.Parent := mPanel;
  FRowsLabel.Caption := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsRows);
  FRowsLabel.Left := 0;
  FRowsLabel.Top := FRowsLabel.ScaleValue(5);
  FRows := TEdit.Create(FPage);
  FRows.Parent := mPanel;
  FRows.Left := cFieldLeft;
  FRows.Top := 1;
  FRows.Width := FRows.ScaleValue(44);
  FRows.NumbersOnly := True;
  FRowsUpDown := TUpDown.Create(FPage);
  FRowsUpDown.Parent := mPanel;
  FRowsUpDown.Associate := FRows;
  FRowsUpDown.Min := TAtlasPluginSettings.cMinVisibleRows;
  FRowsUpDown.Max := TAtlasPluginSettings.cMaxVisibleRows;
  FAutoWidth := AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsAutoWidth));
  FAutoWidth.OnClick := AutoWidthClick;
  BindText('OpenDelayMs', AddNumber(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsOpenDelay)));
  BindCheck('PanelCollapsed', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsPanelCollapsed)));
  BindCheck('SelectionMarker', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsSelectionMarker)));
  BindCheck('FilterChips', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsChips)));
  BindCheck('Learning', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsLearning)));
  FFavorites := BindCheck('Favorites', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsFavorites)));
  BindCheck('GroupInherited', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsGroupInherited)));
  BindCheck('CompletionVariantBranch',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsCompletionVariantBranch)));
  // In der Reihenfolge von TAtlasListMode bzw. TAtlasListScope.
  FListMode := AddChoice(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsListMode),
    [TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsListModeFilter),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsListModeAll),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsListModeRest)]);
  FListScope := AddChoice(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsListScope),
    [TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsListScopeMembers),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsListScopeEverywhere)]);
  BindCheck('Preview', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsPreview)));
  // Gelernte Vorschläge (#1890): Schattentext nach Enter aus dem eigenen Code.
  BindCheck('SuggestionsLearned', AddCheck(TAtlasLearnedTexts.Text(TAtlasLearnedText.SettingLearned)));
  BindText('SuggestionsDelayMs', AddNumber(TAtlasLearnedTexts.Text(TAtlasLearnedText.SettingDelay)));
  BindText('SuggestionsMinShare', AddNumber(TAtlasLearnedTexts.Text(TAtlasLearnedText.SettingMinShare)));
  BindText('SuggestionsMinCount', AddNumber(TAtlasLearnedTexts.Text(TAtlasLearnedText.SettingMinCount)));
  BindCheck('SuggestionsLearnFromUsage', AddCheck(TAtlasLearnedTexts.Text(TAtlasLearnedText.SettingLearnFromUsage)));
  mPanel := AddPanel(32);
  FResetHistory := TButton.Create(FPage);
  FResetHistory.Parent := mPanel;
  FResetHistory.Caption := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsResetHistory);
  FResetHistory.Left := 0;
  FResetHistory.Top := FResetHistory.ScaleValue(3);
  FResetHistory.Width := FResetHistory.ScaleValue(150);
  FResetHistory.OnClick := ResetHistoryClick;
  FResetWidths := TButton.Create(FPage);
  FResetWidths.Parent := mPanel;
end;

procedure TAtlasSettingsCompletionPart.Build2;
begin
  FResetWidths.Caption := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsResetWidths);
  FResetWidths.Left := FResetWidths.ScaleValue(160);
  FResetWidths.Top := FResetWidths.ScaleValue(3);
  FResetWidths.Width := FResetWidths.ScaleValue(150);
  FResetWidths.OnClick := ResetWidthsClick;
end;

procedure TAtlasSettingsCompletionPart.BindMarks;
begin
  FPage.Marks.Bind(FRows, ['VisibleRows']);
  FPage.Marks.Bind(FListMode, ['CompletionListMode']);
  FPage.Marks.Bind(FListScope, ['CompletionListScope']);
end;

procedure TAtlasSettingsCompletionPart.Load(const ASettings: TAtlasPluginSettings);
begin
  FListWidth := ASettings.ListWidth;
  FPanelWidth := ASettings.PanelWidth;
  FRowsUpDown.Position := ASettings.VisibleRows;
  FAutoWidth.OnClick := nil;
  FAutoWidth.Checked := ASettings.ListWidth = 0;
  FAutoWidth.OnClick := AutoWidthClick;
  FListMode.Choice := Ord(TAtlasListModes.ModeOf(ASettings.CompletionListMode));
  FListScope.Choice := Ord(TAtlasListModes.ScopeOf(ASettings.CompletionListScope));
end;

procedure TAtlasSettingsCompletionPart.Save(var ASettings: TAtlasPluginSettings);
begin
  ASettings.ListWidth := FListWidth;
  ASettings.PanelWidth := FPanelWidth;
  ASettings.VisibleRows := FRowsUpDown.Position;
  if (FListMode.Choice >= Ord(Low(TAtlasListMode))) and (FListMode.Choice <= Ord(High(TAtlasListMode))) then
  begin
    ASettings.CompletionListMode := TAtlasListModes.cModeNames[TAtlasListMode(FListMode.Choice)];
  end;
  if (FListScope.Choice >= Ord(Low(TAtlasListScope))) and (FListScope.Choice <= Ord(High(TAtlasListScope))) then
  begin
    ASettings.CompletionListScope := TAtlasListModes.cScopeNames[TAtlasListScope(FListScope.Choice)];
  end;
end;

procedure TAtlasSettingsCompletionPart.AutoWidthClick(Sender: TObject);
begin
  // Automatisch: gezogene Breite vergessen; aus: die zuletzt gezogene bzw. die Vorgabe.
  if FAutoWidth.Checked then
  begin
    FListWidth := 0;
  end
  else if FListWidth = 0 then
  begin
    FListWidth := TAtlasPluginSettings.cMinListWidth + 160;
  end;
end;

procedure TAtlasSettingsCompletionPart.ResetHistoryClick(Sender: TObject);
begin
  if Assigned(FOnResetHistory) then
  begin
    FOnResetHistory();
  end;
  Allow(FResetHistory, False);
end;

procedure TAtlasSettingsCompletionPart.ResetWidthsClick(Sender: TObject);
begin
  FListWidth := TAtlasPluginSettings.Defaults.ListWidth;
  FPanelWidth := TAtlasPluginSettings.Defaults.PanelWidth;
  FAutoWidth.OnClick := nil;
  FAutoWidth.Checked := FListWidth = 0;
  FAutoWidth.OnClick := AutoWidthClick;
  Allow(FResetWidths, False);
end;

{ TAtlasSettingsFavoritesPart }

procedure TAtlasSettingsFavoritesPart.Build;
var
  mPanel: TWinControl;
  mFavorites: TCheckBox;
begin
  mFavorites := FPage.Part<TAtlasSettingsCompletionPart>.FavoritesCheck;
  AddTitle(TAtlasTextId.SettingsFavoritesTitle);
  mPanel := AddPanel(80);
  FFavoritesList := TListBox.Create(FPage);
  FFavoritesList.Parent := mPanel;
  FFavoritesList.Align := alClient;
  FFavoritesList.MultiSelect := True;
  mPanel := AddPanel(32);
  FFavoritesRemove := TButton.Create(FPage);
  FFavoritesRemove.Parent := mPanel;
  FFavoritesRemove.Caption := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsFavoritesRemove);
  FFavoritesRemove.Left := 0;
  FFavoritesRemove.Top := FFavoritesRemove.ScaleValue(3);
  FFavoritesRemove.Width := FFavoritesRemove.ScaleValue(150);
  FFavoritesRemove.OnClick := FavoritesRemoveClick;
  FFavoritesRemoveAll := TButton.Create(FPage);
  FFavoritesRemoveAll.Parent := mPanel;
  FFavoritesRemoveAll.Caption := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsFavoritesRemoveAll);
  FFavoritesRemoveAll.Left := FFavoritesRemoveAll.ScaleValue(160);
  FFavoritesRemoveAll.Top := FFavoritesRemoveAll.ScaleValue(3);
  FFavoritesRemoveAll.Width := FFavoritesRemoveAll.ScaleValue(150);
  FFavoritesRemoveAll.OnClick := FavoritesRemoveAllClick;
  Attach(FFavoritesList.Parent, mFavorites);
  Attach(mPanel, mFavorites);
end;

procedure TAtlasSettingsFavoritesPart.WindowReady;
begin
  RefreshFavorites;
end;

procedure TAtlasSettingsFavoritesPart.SetOnFavorites(const AValue: TFunc<TArray<TAtlasFavorite>>);
begin
  FOnFavorites := AValue;
  RefreshFavorites;
end;

procedure TAtlasSettingsFavoritesPart.RefreshFavorites;
var
  mFavorites: TArray<TAtlasFavorite>;
  mFavorite: TAtlasFavorite;
  mAny: Boolean;
begin
  // Wie die Liste der Sicherung: ohne Fenster folgt das in CreateWnd.
  if not FPage.HandleAllocated then
  begin
    Exit;
  end;
  mFavorites := nil;
  if Assigned(FOnFavorites) then
  begin
    mFavorites := FOnFavorites();
  end;
  FFavoriteKeys := nil;
  mAny := Length(mFavorites) > 0;
  FFavoritesList.Items.BeginUpdate;
  try
    FFavoritesList.Items.Clear;
    for mFavorite in mFavorites do
    begin
      FFavoritesList.Items.Add(mFavorite.DisplayName);
      FFavoriteKeys := FFavoriteKeys + [mFavorite.Key];
    end;
    if not mAny then
    begin
      FFavoritesList.Items.Add(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsFavoritesNone));
    end;
  finally
    FFavoritesList.Items.EndUpdate;
  end;
  Allow(FFavoritesList, mAny);
  Allow(FFavoritesRemove, mAny and Assigned(FOnRemoveFavorites));
  Allow(FFavoritesRemoveAll, mAny and Assigned(FOnRemoveFavorites));
end;

procedure TAtlasSettingsFavoritesPart.FavoritesRemoveClick(Sender: TObject);
var
  mKeys: TArray<string>;
  mIndex: Integer;
begin
  if not Assigned(FOnRemoveFavorites) then
  begin
    Exit;
  end;
  mKeys := nil;
  for mIndex := 0 to Min(FFavoritesList.Items.Count, Length(FFavoriteKeys)) - 1 do
  begin
    if FFavoritesList.Selected[mIndex] then
    begin
      mKeys := mKeys + [FFavoriteKeys[mIndex]];
    end;
  end;
  if Length(mKeys) = 0 then
  begin
    Exit;
  end;
  FOnRemoveFavorites(mKeys);
  RefreshFavorites;
end;

procedure TAtlasSettingsFavoritesPart.FavoritesRemoveAllClick(Sender: TObject);
begin
  if not Assigned(FOnRemoveFavorites) or (Length(FFavoriteKeys) = 0) then
  begin
    Exit;
  end;
  FOnRemoveFavorites(Copy(FFavoriteKeys));
  RefreshFavorites;
end;

end.
