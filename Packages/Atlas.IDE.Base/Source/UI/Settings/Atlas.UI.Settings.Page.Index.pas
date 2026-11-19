unit Atlas.UI.Settings.Page.Index;

// Reiter „Index“ (#492): Umfang, Kennzahlen, neu aufbauen und löschen über den Server (#874).

interface

uses
  System.SysUtils,
  Vcl.StdCtrls,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.Page.Host;

type
  /// <summary>Reiter „Index“ (#492): Umfang, Kennzahlen, neu aufbauen und löschen über den Server (#874).</summary>
  TAtlasSettingsIndexPart = class(TAtlasSettingsPagePart)
  private
    FIndexInfo: TLabel;
    FIndexRefresh: TButton;
    FIndexRebuild: TButton;
    FIndexClear: TButton;
    FOnIndexMetrics: TProc;
    FOnIndexRebuild: TProc;
    FOnIndexClear: TProc;
    /// <summary>Ein Befehl des Index läuft; Antwort über IndexAnswered (#874).</summary>
    FIndexBusy: Boolean;
    FConfirmClear: TFunc<Boolean>;
    procedure AddIndexSection;
    procedure IndexRefreshClick(Sender: TObject);
    procedure IndexRebuildClick(Sender: TObject);
    procedure IndexClearClick(Sender: TObject);
    procedure UpdateIndexButtons;
    /// <summary>Startet ACommand und zeigt bis zur Antwort „Frage den Server …“ (#874).</summary>
    procedure StartIndexCommand(const ACommand: TProc);
  public
    procedure Build;
    procedure Load(const ASettings: TAtlasPluginSettings); override;
    /// <summary>Kennzahlen des Index neu holen und anzeigen (#492).</summary>
    procedure RefreshIndex;
    /// <summary>Antwort auf OnIndexMetrics, OnIndexRebuild oder OnIndexClear (#874): Text anzeigen, Knöpfe
    /// wieder frei. Darf auch noch während des Ereignisses kommen.</summary>
    procedure IndexAnswered(const AText: string);
    /// <summary>Wartet die Seite auf eine Antwort des Index (#874)?</summary>
    function IndexBusy: Boolean;
    /// <summary>Zum Testen: Kennzahlen und Schaltflächen des Index.</summary>
    property IndexInfo: TLabel read FIndexInfo;
    property IndexRebuild: TButton read FIndexRebuild;
    property IndexClear: TButton read FIndexClear;
    /// <summary>Kennzahlen im Hintergrund holen; den Text liefert IndexAnswered. nil = nicht verfügbar.</summary>
    property OnIndexMetrics: TProc read FOnIndexMetrics write FOnIndexMetrics;
    /// <summary>„Index neu aufbauen“ bzw. „Index löschen“ im Hintergrund; das Ergebnis liefert IndexAnswered.</summary>
    property OnIndexRebuild: TProc read FOnIndexRebuild write FOnIndexRebuild;
    property OnIndexClear: TProc read FOnIndexClear write FOnIndexClear;
    /// <summary>Rückfrage vor dem Löschen; Standard: Dialog mit Ja/Nein.</summary>
    property ConfirmClear: TFunc<Boolean> read FConfirmClear write FConfirmClear;
  end;

implementation

uses
  System.UITypes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Dialogs,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Strings,
  Atlas.UI.Settings.Page.Sheets;

const
  /// <summary>Höhe der Kennzahlen des Index (vier Zeilen Text).</summary>
  cIndexInfoHeight = 66;

{ TAtlasSettingsIndexPart }

procedure TAtlasSettingsIndexPart.Load(const ASettings: TAtlasPluginSettings);
begin
  RefreshIndex;
end;

procedure TAtlasSettingsIndexPart.AddIndexSection;
var
  mPanel: TWinControl;
begin
  // Symbolindex (#492): Verwendungen, Speichergrenze, Kennzahlen und Verwaltung.
  AddTitle(TAtlasTextId.SettingsIndexTitle);
  BindCheck('IndexUsages', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsIndexUsages)));
  BindText('MemoryBudgetMb', AddNumber(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMemoryBudget)));
  mPanel := AddPanel(cIndexInfoHeight);
  FIndexInfo := TLabel.Create(FPage);
  FIndexInfo.Parent := mPanel;
  FIndexInfo.Left := 0;
  FIndexInfo.Top := FIndexInfo.ScaleValue(2);
  FIndexInfo.Font.Color := clGrayText;
  mPanel := AddPanel(cButtonRowHeight);
  FIndexRefresh := AddColumnButton(mPanel, 0, TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsIndexRefresh),
    IndexRefreshClick);
  FIndexRebuild := AddColumnButton(mPanel, 1, TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsIndexRebuild),
    IndexRebuildClick);
  FIndexClear := AddColumnButton(mPanel, 2, TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsIndexClear),
    IndexClearClick);
  // Ohne Server (Ereignisse nicht gesetzt) sind die Befehle aus.
  RefreshIndex;
end;

procedure TAtlasSettingsIndexPart.IndexRefreshClick(Sender: TObject);
begin
  RefreshIndex;
end;

procedure TAtlasSettingsIndexPart.IndexRebuildClick(Sender: TObject);
begin
  StartIndexCommand(FOnIndexRebuild);
end;

procedure TAtlasSettingsIndexPart.IndexClearClick(Sender: TObject);
var
  mConfirmed: Boolean;
begin
  if not Assigned(FOnIndexClear) then
  begin
    Exit;
  end;
  if Assigned(FConfirmClear) then
  begin
    mConfirmed := FConfirmClear();
  end
  else
  begin
    mConfirmed := MessageDlg(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsIndexClearConfirm), mtConfirmation,
      [mbYes, mbNo], 0) = mrYes;
  end;
  if mConfirmed then
  begin
    StartIndexCommand(FOnIndexClear);
  end;
end;

procedure TAtlasSettingsIndexPart.UpdateIndexButtons;
begin
  Allow(FIndexRefresh, Assigned(FOnIndexMetrics) and not FIndexBusy);
  Allow(FIndexRebuild, Assigned(FOnIndexRebuild) and not FIndexBusy);
  Allow(FIndexClear, Assigned(FOnIndexClear) and not FIndexBusy);
end;

procedure TAtlasSettingsIndexPart.StartIndexCommand(const ACommand: TProc);
begin
  if not Assigned(ACommand) or FIndexBusy then
  begin
    Exit;
  end;
  FIndexBusy := True;
  FIndexInfo.Caption := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsIndexAsking);
  UpdateIndexButtons;
  ACommand();
end;

procedure TAtlasSettingsIndexPart.Build;
begin
  // Umfang des Index für alle Projekte, gespeichert in settings.json (index.*, #652, #227).
  AddSheet(TAtlasTextId.SettingsTabIndex);
  BindCheck('IndexProjectGroup', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsIndexGroup)));
  BindCheck('IndexSearchPaths', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsIndexSearch)));
  BindCheck('IndexLibraryPaths', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsIndexLibrary)));
  AddIndexSection;
end;

procedure TAtlasSettingsIndexPart.RefreshIndex;
begin
  if Assigned(FOnIndexMetrics) then
  begin
    StartIndexCommand(FOnIndexMetrics);
  end
  else if not FIndexBusy then
  begin
    FIndexInfo.Caption := '';
  end;
  UpdateIndexButtons;
end;

procedure TAtlasSettingsIndexPart.IndexAnswered(const AText: string);
begin
  FIndexBusy := False;
  FIndexInfo.Caption := AText;
  UpdateIndexButtons;
end;

function TAtlasSettingsIndexPart.IndexBusy: Boolean;
begin
  Result := FIndexBusy;
end;

end.
