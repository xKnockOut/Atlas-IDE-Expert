unit Atlas.UI.Tracker.QueryDialog;

// Dialog „Abfrage bearbeiten“ (#1263) aus der Tabelle „Abfragen“ der Seite
// Issue-Tracker (#1262): Name, Verbindung, Tracker-Projekt, Abfrage, Vorlagen
// und der Knopf „Testen“.
// - Vorlagen (Atlas.Core.Tracker.Templates) je Anbieter der gewählten
//   Verbindung (ohne Verbindung: aller Verbindungen), bei YouTrack in der
//   erkannten Sprache, sonst Deutsch und Englisch.
// - „Testen“ schickt die Abfrage samt Projekt einmal an den Tracker der
//   gewählten Verbindung (ohne Verbindung: der ersten); das Netz macht der
//   Aufrufer im Hintergrund (OnTest, höchstens 5 s), das Ergebnis kommt im
//   Hauptthread über ShowResult. Ist der Dialog dann schon zu, verfällt es.
// - ResultText: Meldung zur Ursache, Tipp auf die deutsche Vorlage und die
//   tatsächlich gesendete Abfrage; nie das Token.
// Reine VCL; gespeichert wird vom Aufrufer.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.Queries,
  Atlas.Core.Tracker.QueryTest,
  Atlas.Core.Tracker.Templates,
  Atlas.UI.Settings.ChoiceBox;

type
  /// <summary>Ergebnis von „Testen“ (#1263), im Hauptthread.</summary>
  TAtlasQueryTestDone = reference to procedure(const AResult: TAtlasTrackerQueryTestResult);
  /// <summary>„Testen“ im Dialog „Abfrage bearbeiten“ (#1263): ATarget (Abfrage, Projekt, Sprache) über
  /// AConnection im Hintergrund abfragen und ADone im Hauptthread aufrufen.</summary>
  TAtlasQueryTestEvent = reference to procedure(const AConnection: TAtlasTrackerConnection;
    const ATarget: TAtlasTrackerTarget; const ADone: TAtlasQueryTestDone);

  TAtlasTrackerQueryDialog = class;

  /// <summary>Verbindung vom laufenden Test zum Dialog; nil, sobald der Dialog weg ist.</summary>
  TAtlasQueryDialogLink = class(TInterfacedObject)
  private
    FDialog: TAtlasTrackerQueryDialog;
  public
    property Dialog: TAtlasTrackerQueryDialog read FDialog write FDialog;
  end;

  /// <summary>Steuerelemente des Dialogs.</summary>
  TAtlasQueryDialogView = record
    Name: TEdit;
    Connection: TAtlasChoiceBox;
    Project: TEdit;
    Query: TEdit;
    Template: TAtlasChoiceBox;
    Test: TButton;
    Result: TMemo;
    Ok: TButton;
    Cancel: TButton;
  end;

  TAtlasTrackerQueryDialog = class(TForm)
  private
    FView: TAtlasQueryDialogView;
    FConnections: TArray<TAtlasTrackerConnection>;
    FTemplates: TArray<TAtlasTrackerTemplate>;
    FTaken: TArray<string>;
    /// <summary>Verbindung der Abfrage, die es nicht mehr gibt; '' ohne.</summary>
    FMissingConnection: string;
    FOnTest: TAtlasQueryTestEvent;
    FLink: TAtlasQueryDialogLink;
    FLinkRef: IInterface;
    FTesting: Boolean;
    procedure BuildFields;
    procedure BuildTest;
    procedure BuildButtons;
    procedure FillConnections(const AConnection: string);
    function AddRow(const ACaption: string; AControl: TWinControl): TPanel;
    function AddButton(AParent: TWinControl; const ACaption: string; AClick: TNotifyEvent): TButton;
    /// <summary>AProvider in die Liste; bei verschiedenen Sprachen desselben Anbieters gelten alle Vorlagen.</summary>
    class procedure AddProvider(var AProviders, ALanguages: TArray<string>; const AProvider, ALanguage: string);
      static;
    procedure FillTemplates;
    procedure Changed(Sender: TObject);
    procedure ConnectionChange(Sender: TObject);
    procedure TemplateChange(Sender: TObject);
    procedure TestClick(Sender: TObject);
    procedure ClearFields;
    procedure OkClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
  public
    /// <summary>AConnections: Verbindungen in der Reihenfolge der Seite; ATaken: Namen der übrigen Abfragen.
    /// </summary>
    constructor CreateDialog(AOwner: TComponent; const AQuery: TAtlasTrackerQuery;
      const AConnections: TArray<TAtlasTrackerConnection>; const ATaken: TArray<string>;
      const AOnTest: TAtlasQueryTestEvent);
    destructor Destroy; override;
    /// <summary>Abfrage aus den Feldern.</summary>
    function Query: TAtlasTrackerQuery;
    /// <summary>Verbindung, über die „Testen“ fragt; False ohne Verbindung.</summary>
    function TestConnection(out AConnection: TAtlasTrackerConnection): Boolean;
    /// <summary>Verbindung wählen (0 = alle, sonst Index + 1); die Vorlagen folgen.</summary>
    procedure SelectConnection(AChoice: Integer);
    /// <summary>Vorlage AIndex (in Templates) in das Feld Abfrage setzen.</summary>
    procedure ApplyTemplate(AIndex: Integer);
    /// <summary>Ergebnis von „Testen“ zeigen.</summary>
    procedure ShowResult(const AResult: TAtlasTrackerQueryTestResult; const AConnectionName: string);
    /// <summary>Text zum Ergebnis: Ursache, Tipp, gesendete Abfrage.</summary>
    class function ResultText(const AResult: TAtlasTrackerQueryTestResult; const AConnectionName: string): string;
      static;
    /// <summary>„YouTrack · Mir zugewiesen (Deutsch)“; GitHub ohne Sprache.</summary>
    class function TemplateCaption(const ATemplate: TAtlasTrackerTemplate): string; static;
    /// <summary>Vorlagen zur Verbindung AChoice (0 = alle, sonst Index + 1 in AConnections).</summary>
    class function TemplatesFor(const AConnections: TArray<TAtlasTrackerConnection>;
      AChoice: Integer): TArray<TAtlasTrackerTemplate>; static;
    /// <summary>Modal; True mit geänderter AQuery bei OK.</summary>
    class function Execute(var AQuery: TAtlasTrackerQuery; const AConnections: TArray<TAtlasTrackerConnection>;
      const ATaken: TArray<string>; const AOnTest: TAtlasQueryTestEvent): Boolean; static;
    property View: TAtlasQueryDialogView read FView;
    property Templates: TArray<TAtlasTrackerTemplate> read FTemplates;
  end;

implementation

uses
  Atlas.UI.Strings,
  Atlas.UI.Tracker.Strings;

const
  cGap = 8;
  cLabelWidth = 110;
  cDialogWidth = 560;
  cFontName = 'Segoe UI';
  cFontSize = 9;
  cRowHeight = 30;
  cControlTop = 4;
  cTestRowHeight = 36;
  cResultHeight = 84;
  cBottomHeight = 44;
  cButtonPadding = 32;
  cMinButtonWidth = 90;
  cButtonHeight = 28;
  cGitHubCaption = 'GitHub';
  cYouTrackCaption = 'YouTrack';

{ TAtlasTrackerQueryDialog }

constructor TAtlasTrackerQueryDialog.CreateDialog(AOwner: TComponent; const AQuery: TAtlasTrackerQuery;
  const AConnections: TArray<TAtlasTrackerConnection>; const ATaken: TArray<string>;
  const AOnTest: TAtlasQueryTestEvent);
begin
  inherited CreateNew(AOwner);
  FConnections := AConnections;
  FTaken := ATaken;
  FOnTest := AOnTest;
  FLink := TAtlasQueryDialogLink.Create;
  FLink.Dialog := Self;
  FLinkRef := FLink;
  Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.QueryDialogTitle);
  BorderStyle := bsDialog;
  BorderIcons := [biSystemMenu];
  Position := poMainFormCenter;
  Font.Name := cFontName;
  Font.Size := cFontSize;
  ClientWidth := ScaleValue(cDialogWidth);
  BuildFields;
  BuildTest;
  BuildButtons;
  FillConnections(AQuery.Connection);
  FView.Name.Text := AQuery.Name;
  FView.Project.Text := AQuery.Project;
  FView.Query.Text := AQuery.Query;
  FillTemplates;
  FView.Name.OnChange := Changed;
  FView.Query.OnChange := Changed;
  FView.Project.OnChange := Changed;
  FView.Connection.OnChange := ConnectionChange;
  FView.Template.OnChange := TemplateChange;
  ActiveControl := FView.Query;
  Changed(nil);
end;

procedure TAtlasTrackerQueryDialog.BuildFields;
begin
  FView.Name := TEdit.Create(Self);
  AddRow(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesQueryName), FView.Name);
  FView.Connection := TAtlasChoiceBox.Create(Self);
  AddRow(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesProjectConnection), FView.Connection);
  FView.Project := TEdit.Create(Self);
  AddRow(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesProjectProject), FView.Project);
  FView.Template := TAtlasChoiceBox.Create(Self);
  AddRow(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.QueryDialogTemplate), FView.Template);
  FView.Query := TEdit.Create(Self);
  AddRow(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesQuery), FView.Query);
end;

procedure TAtlasTrackerQueryDialog.BuildTest;
var
  mTestRow: TPanel;
begin
  mTestRow := TPanel.Create(Self);
  mTestRow.Parent := Self;
  mTestRow.Align := alTop;
  mTestRow.Top := ClientHeight;
  mTestRow.Height := ScaleValue(cTestRowHeight);
  mTestRow.BevelOuter := bvNone;
  FView.Test := AddButton(mTestRow, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.QueryDialogTest), TestClick);
  FView.Test.Left := ScaleValue(cGap + cLabelWidth);
  FView.Test.Anchors := [akTop, akLeft];
  FView.Result := TMemo.Create(Self);
  FView.Result.Parent := Self;
  FView.Result.Align := alTop;
  FView.Result.Top := ClientHeight;
  FView.Result.AlignWithMargins := True;
  FView.Result.Margins.SetBounds(ScaleValue(cGap + cLabelWidth), 0, ScaleValue(cGap), ScaleValue(cGap));
  FView.Result.Height := ScaleValue(cResultHeight);
  FView.Result.ReadOnly := True;
  FView.Result.WordWrap := True;
  FView.Result.ScrollBars := ssVertical;
  FView.Result.TabStop := False;
end;

procedure TAtlasTrackerQueryDialog.BuildButtons;
var
  mBottom: TPanel;
begin
  mBottom := TPanel.Create(Self);
  mBottom.Parent := Self;
  mBottom.Align := alBottom;
  mBottom.Height := ScaleValue(cBottomHeight);
  mBottom.BevelOuter := bvNone;
  FView.Cancel := AddButton(mBottom, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.QueryDialogCancel), CancelClick);
  FView.Cancel.Cancel := True;
  FView.Cancel.Left := mBottom.ClientWidth - FView.Cancel.Width - ScaleValue(cGap);
  FView.Ok := AddButton(mBottom, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.QueryDialogOk), OkClick);
  FView.Ok.Default := True;
  FView.Ok.Left := FView.Cancel.Left - FView.Ok.Width - ScaleValue(cGap);
  ClientHeight := FView.Result.Top + FView.Result.Height + ScaleValue(cGap) + mBottom.Height;
end;

procedure TAtlasTrackerQueryDialog.FillConnections(const AConnection: string);
var
  mNames: TArray<string>;
  mChoice: Integer;
  mIndex: Integer;
begin
  // Auswahl: „(alle)“, dann die Verbindungen (wie die Tabelle).
  mNames := TArray<string>.Create(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesQueryAny));
  mChoice := 0;
  for mIndex := 0 to High(FConnections) do
  begin
    mNames := mNames + [FConnections[mIndex].Name];
    if (AConnection <> '') and SameText(FConnections[mIndex].Name, AConnection) then
    begin
      mChoice := mIndex + 1;
    end;
  end;
  // Eine Verbindung, die es nicht mehr gibt, bleibt sichtbar, bis der Benutzer eine andere wählt.
  FMissingConnection := '';
  if (AConnection <> '') and (mChoice = 0) then
  begin
    FMissingConnection := AConnection;
    mNames := mNames + [AConnection];
    mChoice := High(mNames);
  end;
  FView.Connection.SetChoices(mNames);
  FView.Connection.Choice := mChoice;
end;

destructor TAtlasTrackerQueryDialog.Destroy;
begin
  // Ein Test, der danach fertig wird, findet keinen Dialog mehr.
  if FLink <> nil then
  begin
    FLink.Dialog := nil;
  end;
  FLinkRef := nil;
  ClearFields;
  inherited Destroy;
end;

procedure TAtlasTrackerQueryDialog.ClearFields;
begin
  FConnections := nil;
  FTemplates := nil;
  FTaken := nil;
  FMissingConnection := '';
end;

function TAtlasTrackerQueryDialog.AddRow(const ACaption: string; AControl: TWinControl): TPanel;
var
  mLabel: TLabel;
begin
  Result := TPanel.Create(Self);
  Result.Parent := Self;
  Result.Align := alTop;
  Result.Top := ClientHeight;
  Result.Height := ScaleValue(cRowHeight);
  Result.BevelOuter := bvNone;
  mLabel := TLabel.Create(Self);
  mLabel.Parent := Result;
  mLabel.Left := ScaleValue(cGap);
  mLabel.Top := ScaleValue(cGap);
  mLabel.Caption := ACaption;
  mLabel.ShowAccelChar := False;
  AControl.Parent := Result;
  AControl.Left := ScaleValue(cGap + cLabelWidth);
  AControl.Top := ScaleValue(cControlTop);
  AControl.Width := Result.ClientWidth - AControl.Left - ScaleValue(cGap);
  AControl.Anchors := [akLeft, akTop, akRight];
  mLabel.FocusControl := AControl;
end;

function TAtlasTrackerQueryDialog.AddButton(AParent: TWinControl; const ACaption: string;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.OnClick := AClick;
  Canvas.Font := Font;
  Result.Width := Canvas.TextWidth(ACaption) + ScaleValue(cButtonPadding);
  if Result.Width < ScaleValue(cMinButtonWidth) then
  begin
    Result.Width := ScaleValue(cMinButtonWidth);
  end;
  Result.Top := ScaleValue(cGap div 2);
  Result.Height := ScaleValue(cButtonHeight);
  Result.Anchors := [akTop, akRight];
end;

class procedure TAtlasTrackerQueryDialog.AddProvider(var AProviders, ALanguages: TArray<string>;
  const AProvider, ALanguage: string);
var
  mOther: Integer;
begin
  for mOther := 0 to High(AProviders) do
  begin
    if SameText(AProviders[mOther], AProvider) then
    begin
      // Verschiedene Sprachen beim selben Anbieter: alle Vorlagen.
      if not SameText(ALanguages[mOther], ALanguage) then
      begin
        ALanguages[mOther] := '';
      end;
      Exit;
    end;
  end;
  AProviders := AProviders + [AProvider];
  ALanguages := ALanguages + [ALanguage];
end;

class function TAtlasTrackerQueryDialog.TemplatesFor(const AConnections: TArray<TAtlasTrackerConnection>;
  AChoice: Integer): TArray<TAtlasTrackerTemplate>;
var
  mProviders: TArray<string>;
  mLanguages: TArray<string>;
  mIndex: Integer;
begin
  Result := nil;
  mProviders := nil;
  mLanguages := nil;
  if (AChoice >= 1) and (AChoice <= Length(AConnections)) then
  begin
    AddProvider(mProviders, mLanguages, AConnections[AChoice - 1].Provider, AConnections[AChoice - 1].Language);
  end
  else
  begin
    for mIndex := 0 to High(AConnections) do
    begin
      AddProvider(mProviders, mLanguages, AConnections[mIndex].Provider, AConnections[mIndex].Language);
    end;
  end;
  // Ohne Verbindung: alle Vorlagen beider Anbieter.
  if Length(mProviders) = 0 then
  begin
    mProviders := TArray<string>.Create(TAtlasTrackerTarget.YouTrack, TAtlasTrackerTarget.GitHub);
    mLanguages := TArray<string>.Create('', '');
  end;
  for mIndex := 0 to High(mProviders) do
  begin
    Result := Result + TAtlasTrackerTemplates.Templates(mProviders[mIndex], mLanguages[mIndex]);
  end;
end;

class function TAtlasTrackerQueryDialog.TemplateCaption(const ATemplate: TAtlasTrackerTemplate): string;
var
  mProvider, mKind: string;
begin
  if ATemplate.Provider = TAtlasTrackerTarget.GitHub then
  begin
    mProvider := cGitHubCaption;
  end
  else
  begin
    mProvider := cYouTrackCaption;
  end;
  case ATemplate.Kind of
    TAtlasTrackerTemplateKind.CurrentSprint:
      mKind := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerTemplateCurrentSprint);
    TAtlasTrackerTemplateKind.CreatedByMe:
      mKind := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerTemplateCreatedByMe);
    TAtlasTrackerTemplateKind.RecentlyChanged:
      mKind := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerTemplateRecentlyChanged);
  else
    mKind := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesQueryDefault);
  end;
  Result := mProvider + ' · ' + mKind;
  // GitHub kennt nur englische Suchbegriffe; die Sprache zu nennen hilft nur bei YouTrack.
  if ATemplate.Provider = TAtlasTrackerTarget.GitHub then
  begin
    Exit;
  end;
  if ATemplate.Language = TAtlasTrackerTemplates.German then
  begin
    Result := Result + ' (' + TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerLanguageGerman) + ')';
  end
  else
  begin
    Result := Result + ' (' + TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerLanguageEnglish) + ')';
  end;
end;

procedure TAtlasTrackerQueryDialog.FillTemplates;
var
  mCaptions: TArray<string>;
  mTemplate: TAtlasTrackerTemplate;
begin
  FTemplates := TemplatesFor(FConnections, FView.Connection.Choice);
  mCaptions := TArray<string>.Create(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.QueryDialogTemplatePick));
  for mTemplate in FTemplates do
  begin
    mCaptions := mCaptions + [TemplateCaption(mTemplate)];
  end;
  FView.Template.SetChoices(mCaptions);
  FView.Template.Choice := 0;
end;

function TAtlasTrackerQueryDialog.Query: TAtlasTrackerQuery;
var
  mChoice: Integer;
  mConnection: string;
begin
  mChoice := FView.Connection.Choice;
  mConnection := '';
  if (mChoice >= 1) and (mChoice <= Length(FConnections)) then
  begin
    mConnection := FConnections[mChoice - 1].Name;
  end
  else if mChoice > Length(FConnections) then
  begin
    // Verbindung, die es nicht mehr gibt: unverändert lassen.
    mConnection := FMissingConnection;
  end;
  Result := TAtlasTrackerQuery.Create(FView.Name.Text, FView.Query.Text, mConnection, FView.Project.Text);
end;

function TAtlasTrackerQueryDialog.TestConnection(out AConnection: TAtlasTrackerConnection): Boolean;
var
  mChoice: Integer;
begin
  mChoice := FView.Connection.Choice;
  Result := Length(FConnections) > 0;
  if not Result then
  begin
    Exit;
  end;
  if (mChoice >= 1) and (mChoice <= Length(FConnections)) then
  begin
    AConnection := FConnections[mChoice - 1];
  end
  else if mChoice = 0 then
  begin
    // „(alle)“: getestet wird über die erste Verbindung.
    AConnection := FConnections[0];
  end
  else
  begin
    Result := False;
  end;
end;

procedure TAtlasTrackerQueryDialog.Changed(Sender: TObject);
var
  mQuery: TAtlasTrackerQuery;
  mTaken: Boolean;
  mName: string;
  mConnection: TAtlasTrackerConnection;
begin
  mQuery := Query;
  mTaken := False;
  for mName in FTaken do
  begin
    if SameText(mName, mQuery.Name) then
    begin
      mTaken := True;
    end;
  end;
  FView.Ok.Enabled := (mQuery.Name <> '') and not mTaken and (mQuery.Query <> '');
  FView.Test.Enabled := not FTesting and Assigned(FOnTest) and TestConnection(mConnection);
  if mTaken then
  begin
    FView.Result.Text := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesQueryNameTaken);
  end;
end;

procedure TAtlasTrackerQueryDialog.ConnectionChange(Sender: TObject);
begin
  FillTemplates;
  Changed(Sender);
end;

procedure TAtlasTrackerQueryDialog.SelectConnection(AChoice: Integer);
begin
  FView.Connection.Choice := AChoice;
  ConnectionChange(FView.Connection);
end;

procedure TAtlasTrackerQueryDialog.TemplateChange(Sender: TObject);
begin
  ApplyTemplate(FView.Template.Choice - 1);
end;

procedure TAtlasTrackerQueryDialog.ApplyTemplate(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FTemplates)) then
  begin
    Exit;
  end;
  FView.Query.Text := FTemplates[AIndex].Query;
  // Zurück auf „(Vorlage einsetzen …)“, damit dieselbe Vorlage noch einmal wählbar bleibt.
  FView.Template.Choice := 0;
  Changed(FView.Template);
end;

procedure TAtlasTrackerQueryDialog.TestClick(Sender: TObject);
var
  mConnection: TAtlasTrackerConnection;
  mTarget: TAtlasTrackerTarget;
  mQuery: TAtlasTrackerQuery;
  mLinkRef: IInterface;
  mLink: TAtlasQueryDialogLink;
  mName: string;
begin
  if FTesting or not Assigned(FOnTest) or not TestConnection(mConnection) then
  begin
    Exit;
  end;
  mQuery := Query;
  // Wie in „Meine Issues“: Projekt aus dem Feld, Abfrage leer = Vorgabe in der Sprache der Verbindung.
  mTarget := TAtlasTrackerTarget.Create(mConnection.Provider, mConnection.Url, mQuery.Project, mQuery.Query);
  mTarget.Language := mConnection.Language;
  FTesting := True;
  FView.Result.Text := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.QueryDialogTesting);
  Changed(Sender);
  mLinkRef := FLinkRef;
  mLink := FLink;
  mName := mConnection.Name;
  FOnTest(mConnection, mTarget,
    procedure(const AResult: TAtlasTrackerQueryTestResult)
    begin
      if (mLinkRef <> nil) and (mLink.Dialog <> nil) then
      begin
        mLink.Dialog.ShowResult(AResult, mName);
      end;
    end);
end;

procedure TAtlasTrackerQueryDialog.ShowResult(const AResult: TAtlasTrackerQueryTestResult;
  const AConnectionName: string);
begin
  FTesting := False;
  FView.Result.Text := ResultText(AResult, AConnectionName);
  Changed(nil);
end;

class function TAtlasTrackerQueryDialog.ResultText(const AResult: TAtlasTrackerQueryTestResult;
  const AConnectionName: string): string;
var
  mLines: TArray<string>;
begin
  case AResult.Outcome of
    TAtlasTrackerQueryOutcome.Found:
      if AResult.More then
      begin
        mLines := [TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.QueryTestFoundMore, [AResult.Count, AResult.ElapsedMs,
          string.Join(', ', AResult.Keys)])];
      end
      else
      begin
        mLines := [TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.QueryTestFound, [AResult.Count, AResult.ElapsedMs,
          string.Join(', ', AResult.Keys)])];
      end;
    TAtlasTrackerQueryOutcome.Empty:
      mLines := [TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.QueryTestEmpty, [AResult.ElapsedMs])];
    TAtlasTrackerQueryOutcome.NoToken:
      mLines := [TAtlasTrackerStrings.Text(TAtlasTrackerTextId.QueryTestNoToken)];
    TAtlasTrackerQueryOutcome.NotConfigured:
      mLines := [TAtlasTrackerStrings.Text(TAtlasTrackerTextId.QueryTestNotConfigured)];
    TAtlasTrackerQueryOutcome.Rejected:
      mLines := [TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.QueryTestRejected, [AResult.HttpStatus])];
    TAtlasTrackerQueryOutcome.ProjectUnknown:
      mLines := [TAtlasTrackerStrings.Text(TAtlasTrackerTextId.QueryTestProjectUnknown)];
    TAtlasTrackerQueryOutcome.QueryRejected:
      mLines := [TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.QueryTestQueryRejected, [AResult.HttpStatus,
        AResult.TrackerMessage])];
    TAtlasTrackerQueryOutcome.Unreadable:
      mLines := [TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.QueryTestUnreadable, [AResult.HttpStatus])];
    TAtlasTrackerQueryOutcome.ServerError:
      mLines := [TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.QueryTestServerError, [AResult.HttpStatus])];
  else
    mLines := [TAtlasTrackerStrings.Text(TAtlasTrackerTextId.QueryTestUnreachable)];
  end;
  if AResult.SuggestedQuery <> '' then
  begin
    mLines := mLines + [TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.QueryTestTipGerman, [AResult.SuggestedQuery])];
  end;
  if AResult.SentQuery <> '' then
  begin
    mLines := mLines + [TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.QueryTestSent,
      [AConnectionName, AResult.SentQuery])];
  end;
  Result := string.Join(sLineBreak, mLines);
end;

procedure TAtlasTrackerQueryDialog.OkClick(Sender: TObject);
begin
  if not FView.Ok.Enabled then
  begin
    Exit;
  end;
  ModalResult := mrOk;
end;

procedure TAtlasTrackerQueryDialog.CancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

class function TAtlasTrackerQueryDialog.Execute(var AQuery: TAtlasTrackerQuery;
  const AConnections: TArray<TAtlasTrackerConnection>; const ATaken: TArray<string>;
  const AOnTest: TAtlasQueryTestEvent): Boolean;
var
  mDialog: TAtlasTrackerQueryDialog;
begin
  mDialog := TAtlasTrackerQueryDialog.CreateDialog(nil, AQuery, AConnections, ATaken, AOnTest);
  try
    Result := mDialog.ShowModal = mrOk;
    if Result then
    begin
      AQuery := mDialog.Query;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
