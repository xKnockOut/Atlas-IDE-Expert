unit Atlas.UI.Tracker.SettingsPaths;

// Feld „Arbeitskopien“ der Tabelle Projekte auf der Seite Issue-Tracker
// (#1926, Mockup Runde 82 TP2): ein Ordner je Zeile, der erste ist die
// Haupt-Arbeitskopie. Darunter „Ordner hinzufügen …“, „Prüfen“ (Art und
// Branch je Ordner über den Haken OnCheckPaths) und „Vorschlagen …“ (#1929,
// nur mit dem Haken OnSuggestPaths). Die Zeile selbst hält
// TAtlasTrackerProjectTable; Änderungen meldet OnChanged mit der neuen Liste.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Atlas.Core.Tracker.Projects,
  Atlas.UI.Tracker.SettingsRows,
  Atlas.UI.Tracker.SuggestDialog;

type
  /// <summary>Ordner aus „Hinzufügen …“ wählen; False bei Abbruch.</summary>
  TAtlasTrackerFolderBrowse = reference to function(out APath: string): Boolean;

  /// <summary>Steuerelemente des Feldes.</summary>
  TAtlasTrackerPathsView = record
    Paths: TMemo;
    Add: TButton;
    Check: TButton;
    Suggest: TButton;
    Note: TLabel;
  end;

  TAtlasTrackerPathsPart = class
  private
    FAlive: IAtlasTrackerPathsAlive;
    FRows: TAtlasTrackerSettingsRows;
    FHooks: TAtlasTrackerSettingsHooks;
    FAnchor: TWinControl;
    FView: TAtlasTrackerPathsView;
    FRow: TAtlasTrackerProjectMapping;
    FEditable: Boolean;
    FFilling: Boolean;
    FGeneration: Integer;
    FBrowse: TAtlasTrackerFolderBrowse;
    FOnChanged: TProc<TArray<string>>;
    procedure PathsChange(Sender: TObject);
    procedure AddClick(Sender: TObject);
    procedure CheckClick(Sender: TObject);
    procedure SuggestClick(Sender: TObject);
    procedure Append(const APaths: TArray<string>);
  public const
    cPathsRow = 64;
    cAddWidth = 140;
  public
    constructor Create(ARows: TAtlasTrackerSettingsRows; AHooks: TAtlasTrackerSettingsHooks; AAnchor: TWinControl;
      const ABrowse: TAtlasTrackerFolderBrowse; const AOnChanged: TProc<TArray<string>>);
    destructor Destroy; override;
    procedure Build;
    /// <summary>Zeile ARow zeigen; AEditable: persönliche Zeile.</summary>
    procedure Show(const ARow: TAtlasTrackerProjectMapping; AEditable: Boolean);
    /// <summary>Spalte „Arbeitskopien“: „(Ordner der Zeile)“, ein Ordner bzw. „Ordner +N“.</summary>
    class function Caption(const ARow: TAtlasTrackerProjectMapping): string; static;
    /// <summary>Zeilen des Feldes als Liste (getrimmt, ohne leere und doppelte).</summary>
    class function PathsOf(const AText: string): TArray<string>; static;
    property View: TAtlasTrackerPathsView read FView;
  end;

implementation

uses
  Atlas.UI.Tracker.Settings.Strings;

const
  cLineBreak = #13#10;
  cNoteSeparator = '; ';

type
  TRows = TAtlasTrackerSettingsRows;

{ TAtlasTrackerPathsPart }

constructor TAtlasTrackerPathsPart.Create(ARows: TAtlasTrackerSettingsRows; AHooks: TAtlasTrackerSettingsHooks;
  AAnchor: TWinControl; const ABrowse: TAtlasTrackerFolderBrowse; const AOnChanged: TProc<TArray<string>>);
begin
  inherited Create;
  FRows := ARows;
  FHooks := AHooks;
  FAnchor := AAnchor;
  FBrowse := ABrowse;
  FOnChanged := AOnChanged;
  FAlive := TAtlasTrackerPathsAlive.Create;
end;

destructor TAtlasTrackerPathsPart.Destroy;
begin
  FAlive.Release;
  FAlive := nil;
  inherited Destroy;
end;

class function TAtlasTrackerPathsPart.Caption(const ARow: TAtlasTrackerProjectMapping): string;
begin
  case Length(ARow.Paths) of
    0:
      Result := TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesPathsOwnFolder);
    1:
      Result := ARow.Paths[0];
  else
    Result := TAtlasOptionsStrings.Fmt(TAtlasOptionsTextId.SettingsIssuesPathsMore,
      [ARow.Paths[0], Length(ARow.Paths) - 1]);
  end;
end;

class function TAtlasTrackerPathsPart.PathsOf(const AText: string): TArray<string>;
begin
  Result := TAtlasTrackerProjects.SplitPaths(AText);
end;

procedure TAtlasTrackerPathsPart.Build;
var
  mPanel: TWinControl;
  mLeft: Integer;
begin
  FView.Paths := TMemo.Create(FRows.Owner);
  FView.Paths.ScrollBars := ssVertical;
  FView.Paths.WantReturns := True;
  FView.Paths.WordWrap := False;
  FView.Paths.OnChange := PathsChange;
  FRows.Attach(FRows.AddTallLabelled(TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesPaths), FView.Paths,
    cPathsRow), FAnchor);
  mPanel := FRows.AddPanel(TRows.cButtonRow);
  mLeft := TRows.cFieldLeft;
  FView.Add := FRows.AddButton(mPanel, mLeft, cAddWidth,
    TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesPathsAdd), AddClick);
  Inc(mLeft, cAddWidth + TRows.cButtonGap);
  FView.Check := FRows.AddButton(mPanel, mLeft, TRows.cButtonWidth,
    TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesPathsCheck), CheckClick);
  Inc(mLeft, TRows.cButtonWidth + TRows.cButtonGap);
  FView.Suggest := FRows.AddButton(mPanel, mLeft, TRows.cButtonWidth,
    TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesPathsSuggest), SuggestClick);
  // Ohne Haken (issues.suggestPaths aus) gibt es den Knopf nicht.
  FView.Suggest.Visible := Assigned(FHooks.OnSuggestPaths);
  FRows.Attach(mPanel, FAnchor);
  FView.Note := FRows.AddNote(FAnchor);
  FRows.AddHint(TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesPathsHint), FAnchor);
end;

procedure TAtlasTrackerPathsPart.Show(const ARow: TAtlasTrackerProjectMapping; AEditable: Boolean);
begin
  FRow := ARow;
  FEditable := AEditable;
  // Ein laufendes „Prüfen“ gehört zur vorigen Zeile.
  Inc(FGeneration);
  if FView.Paths = nil then
  begin
    Exit;
  end;
  FFilling := True;
  try
    FView.Paths.Text := string.Join(cLineBreak, ARow.Paths);
  finally
    FFilling := False;
  end;
  FView.Note.Caption := '';
  FRows.Allow(FView.Paths, AEditable);
  FRows.Allow(FView.Add, AEditable);
  FRows.Allow(FView.Check, Assigned(FHooks.OnCheckPaths) and (ARow.Match <> ''));
  FRows.Allow(FView.Suggest, AEditable);
end;

procedure TAtlasTrackerPathsPart.PathsChange(Sender: TObject);
begin
  if FFilling or not FEditable then
  begin
    Exit;
  end;
  FRow.Paths := PathsOf(FView.Paths.Text);
  if Assigned(FOnChanged) then
  begin
    FOnChanged(FRow.Paths);
  end;
end;

procedure TAtlasTrackerPathsPart.Append(const APaths: TArray<string>);
var
  mText: string;
begin
  mText := Trim(FView.Paths.Text);
  if mText <> '' then
  begin
    mText := mText + cLineBreak;
  end;
  // OnChange übernimmt die Liste (doppelte fallen dort weg).
  FView.Paths.Text := mText + string.Join(cLineBreak, APaths);
end;

procedure TAtlasTrackerPathsPart.AddClick(Sender: TObject);
var
  mPath: string;
begin
  if FEditable and Assigned(FBrowse) and FBrowse(mPath) and (Trim(mPath) <> '') then
  begin
    Append([mPath]);
  end;
end;

procedure TAtlasTrackerPathsPart.CheckClick(Sender: TObject);
var
  mGeneration: Integer;
  mOwner: TAtlasTrackerPathsPart;
  mAlive: IAtlasTrackerPathsAlive;
begin
  if not Assigned(FHooks.OnCheckPaths) then
  begin
    Exit;
  end;
  Inc(FGeneration);
  mGeneration := FGeneration;
  mOwner := Self;
  mAlive := FAlive;
  FView.Note.Caption := TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesPathsChecking);
  FHooks.OnCheckPaths(FRow.Folders,
    procedure(ALines: TArray<string>)
    begin
      // Andere Zeile gewählt oder Seite zu: das Ergebnis gilt nicht mehr.
      if mAlive.Alive and (mGeneration = mOwner.FGeneration) and mOwner.FRows.Active then
      begin
        mOwner.FView.Note.Caption := string.Join(cNoteSeparator, ALines);
      end;
    end);
end;

procedure TAtlasTrackerPathsPart.SuggestClick(Sender: TObject);
var
  mPaths: TArray<string>;
begin
  if not (FEditable and Assigned(FHooks.OnSuggestPaths) and FHooks.OnSuggestPaths(FRow, mPaths)) then
  begin
    Exit;
  end;
  // Leer nach „Nichts gefunden – Ordner selbst wählen …“.
  if Length(mPaths) = 0 then
  begin
    AddClick(Sender);
    Exit;
  end;
  Append(mPaths);
end;

end.
