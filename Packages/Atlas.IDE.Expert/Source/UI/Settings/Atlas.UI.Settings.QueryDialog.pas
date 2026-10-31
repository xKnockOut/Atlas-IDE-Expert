unit Atlas.UI.Settings.QueryDialog;

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
  public
    Dialog: TAtlasTrackerQueryDialog;
  end;

  TAtlasTrackerQueryDialog = class(TForm)
  private
    FName: TEdit;
    FConnection: TAtlasChoiceBox;
    FProject: TEdit;
    FQuery: TEdit;
    FTemplate: TAtlasChoiceBox;
    FTest: TButton;
    FResult: TMemo;
    FOk: TButton;
    FCancel: TButton;
    FConnections: TArray<TAtlasTrackerConnection>;
    FTemplates: TArray<TAtlasTrackerTemplate>;
    FTaken: TArray<string>;
    /// <summary>Verbindung der Abfrage, die es nicht mehr gibt; '' ohne.</summary>
    FMissingConnection: string;
    FOnTest: TAtlasQueryTestEvent;
    FLink: TAtlasQueryDialogLink;
    FLinkRef: IInterface;
    FTesting: Boolean;
    function AddRow(const ACaption: string; AControl: TWinControl): TPanel;
    function AddButton(AParent: TWinControl; const ACaption: string; AClick: TNotifyEvent): TButton;
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
    property NameEdit: TEdit read FName;
    property ConnectionBox: TAtlasChoiceBox read FConnection;
    property ProjectEdit: TEdit read FProject;
    property QueryEdit: TEdit read FQuery;
    property TemplateBox: TAtlasChoiceBox read FTemplate;
    property TestButton: TButton read FTest;
    property ResultMemo: TMemo read FResult;
    property OkButton: TButton read FOk;
    property Templates: TArray<TAtlasTrackerTemplate> read FTemplates;
  end;

implementation

uses
  Atlas.UI.Strings;

const
  cGap = 8;
  cLabelWidth = 110;
  cDialogWidth = 560;

{ TAtlasTrackerQueryDialog }

constructor TAtlasTrackerQueryDialog.CreateDialog(AOwner: TComponent; const AQuery: TAtlasTrackerQuery;
  const AConnections: TArray<TAtlasTrackerConnection>; const ATaken: TArray<string>;
  const AOnTest: TAtlasQueryTestEvent);
var
  mBottom, mTestRow: TPanel;
  mNames: TArray<string>;
  mConnection: TAtlasTrackerConnection;
  mChoice, mIndex: Integer;
begin
  inherited CreateNew(AOwner);
  FConnections := AConnections;
  FTaken := ATaken;
  FOnTest := AOnTest;
  FLink := TAtlasQueryDialogLink.Create;
  FLink.Dialog := Self;
  FLinkRef := FLink;
  Caption := TAtlasStrings.Text(TAtlasTextId.QueryDialogTitle);
  BorderStyle := bsDialog;
  BorderIcons := [biSystemMenu];
  Position := poMainFormCenter;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := ScaleValue(cDialogWidth);

  FName := TEdit.Create(Self);
  AddRow(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesQueryName), FName);
  FConnection := TAtlasChoiceBox.Create(Self);
  AddRow(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectConnection), FConnection);
  FProject := TEdit.Create(Self);
  AddRow(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectProject), FProject);
  FTemplate := TAtlasChoiceBox.Create(Self);
  AddRow(TAtlasStrings.Text(TAtlasTextId.QueryDialogTemplate), FTemplate);
  FQuery := TEdit.Create(Self);
  AddRow(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesQuery), FQuery);

  mTestRow := TPanel.Create(Self);
  mTestRow.Parent := Self;
  mTestRow.Align := alTop;
  mTestRow.Top := ClientHeight;
  mTestRow.Height := ScaleValue(36);
  mTestRow.BevelOuter := bvNone;
  FTest := AddButton(mTestRow, TAtlasStrings.Text(TAtlasTextId.QueryDialogTest), TestClick);
  FTest.Left := ScaleValue(cGap + cLabelWidth);
  FTest.Anchors := [akTop, akLeft];

  FResult := TMemo.Create(Self);
  FResult.Parent := Self;
  FResult.Align := alTop;
  FResult.Top := ClientHeight;
  FResult.AlignWithMargins := True;
  FResult.Margins.SetBounds(ScaleValue(cGap + cLabelWidth), 0, ScaleValue(cGap), ScaleValue(cGap));
  FResult.Height := ScaleValue(84);
  FResult.ReadOnly := True;
  FResult.WordWrap := True;
  FResult.ScrollBars := ssVertical;
  FResult.TabStop := False;

  mBottom := TPanel.Create(Self);
  mBottom.Parent := Self;
  mBottom.Align := alBottom;
  mBottom.Height := ScaleValue(44);
  mBottom.BevelOuter := bvNone;
  FCancel := AddButton(mBottom, TAtlasStrings.Text(TAtlasTextId.QueryDialogCancel), CancelClick);
  FCancel.Cancel := True;
  FCancel.Left := mBottom.ClientWidth - FCancel.Width - ScaleValue(cGap);
  FOk := AddButton(mBottom, TAtlasStrings.Text(TAtlasTextId.QueryDialogOk), OkClick);
  FOk.Default := True;
  FOk.Left := FCancel.Left - FOk.Width - ScaleValue(cGap);
  ClientHeight := FResult.Top + FResult.Height + ScaleValue(cGap) + mBottom.Height;

  // Auswahl: „(alle)“, dann die Verbindungen (wie die Tabelle).
  mNames := TArray<string>.Create(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesQueryAny));
  mChoice := 0;
  for mIndex := 0 to High(FConnections) do
  begin
    mConnection := FConnections[mIndex];
    mNames := mNames + [mConnection.Name];
    if (AQuery.Connection <> '') and SameText(mConnection.Name, AQuery.Connection) then
      mChoice := mIndex + 1;
  end;
  // Eine Verbindung, die es nicht mehr gibt, bleibt sichtbar, bis der Benutzer eine andere wählt.
  FMissingConnection := '';
  if (AQuery.Connection <> '') and (mChoice = 0) then
  begin
    FMissingConnection := AQuery.Connection;
    mNames := mNames + [AQuery.Connection];
    mChoice := High(mNames);
  end;
  FConnection.SetChoices(mNames);
  FConnection.Choice := mChoice;
  FName.Text := AQuery.Name;
  FProject.Text := AQuery.Project;
  FQuery.Text := AQuery.Query;
  FillTemplates;
  FName.OnChange := Changed;
  FQuery.OnChange := Changed;
  FProject.OnChange := Changed;
  FConnection.OnChange := ConnectionChange;
  FTemplate.OnChange := TemplateChange;
  ActiveControl := FQuery;
  Changed(nil);
end;

destructor TAtlasTrackerQueryDialog.Destroy;
begin
  // Ein Test, der danach fertig wird, findet keinen Dialog mehr.
  if FLink <> nil then
    FLink.Dialog := nil;
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
  Result.Height := ScaleValue(30);
  Result.BevelOuter := bvNone;
  mLabel := TLabel.Create(Self);
  mLabel.Parent := Result;
  mLabel.Left := ScaleValue(cGap);
  mLabel.Top := ScaleValue(cGap);
  mLabel.Caption := ACaption;
  mLabel.ShowAccelChar := False;
  AControl.Parent := Result;
  AControl.Left := ScaleValue(cGap + cLabelWidth);
  AControl.Top := ScaleValue(4);
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
  Result.Width := Canvas.TextWidth(ACaption) + ScaleValue(32);
  if Result.Width < ScaleValue(90) then
    Result.Width := ScaleValue(90);
  Result.Top := ScaleValue(cGap div 2);
  Result.Height := ScaleValue(28);
  Result.Anchors := [akTop, akRight];
end;

class function TAtlasTrackerQueryDialog.TemplatesFor(const AConnections: TArray<TAtlasTrackerConnection>;
  AChoice: Integer): TArray<TAtlasTrackerTemplate>;
var
  mProviders, mLanguages: TArray<string>;
  mIndex, mOther: Integer;
  mSeen: Boolean;
begin
  Result := nil;
  mProviders := nil;
  mLanguages := nil;
  if (AChoice >= 1) and (AChoice <= Length(AConnections)) then
  begin
    mProviders := [AConnections[AChoice - 1].Provider];
    mLanguages := [AConnections[AChoice - 1].Language];
  end
  else
    for mIndex := 0 to High(AConnections) do
    begin
      mSeen := False;
      for mOther := 0 to High(mProviders) do
        if SameText(mProviders[mOther], AConnections[mIndex].Provider) then
        begin
          // Verschiedene Sprachen beim selben Anbieter: alle Vorlagen.
          if not SameText(mLanguages[mOther], AConnections[mIndex].Language) then
            mLanguages[mOther] := '';
          mSeen := True;
        end;
      if mSeen then
        Continue;
      mProviders := mProviders + [AConnections[mIndex].Provider];
      mLanguages := mLanguages + [AConnections[mIndex].Language];
    end;
  // Ohne Verbindung: alle Vorlagen beider Anbieter.
  if Length(mProviders) = 0 then
  begin
    mProviders := TArray<string>.Create(TAtlasTrackerTarget.YouTrack, TAtlasTrackerTarget.GitHub);
    mLanguages := TArray<string>.Create('', '');
  end;
  for mIndex := 0 to High(mProviders) do
    Result := Result + TAtlasTrackerTemplates.Templates(mProviders[mIndex], mLanguages[mIndex]);
end;

class function TAtlasTrackerQueryDialog.TemplateCaption(const ATemplate: TAtlasTrackerTemplate): string;
var
  mProvider, mKind: string;
begin
  if ATemplate.Provider = TAtlasTrackerTarget.GitHub then
    mProvider := 'GitHub'
  else
    mProvider := 'YouTrack';
  case ATemplate.Kind of
    TAtlasTrackerTemplateKind.CurrentSprint:
      mKind := TAtlasStrings.Text(TAtlasTextId.TrackerTemplateCurrentSprint);
    TAtlasTrackerTemplateKind.CreatedByMe:
      mKind := TAtlasStrings.Text(TAtlasTextId.TrackerTemplateCreatedByMe);
    TAtlasTrackerTemplateKind.RecentlyChanged:
      mKind := TAtlasStrings.Text(TAtlasTextId.TrackerTemplateRecentlyChanged);
  else
    mKind := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesQueryDefault);
  end;
  Result := mProvider + ' · ' + mKind;
  // GitHub kennt nur englische Suchbegriffe; die Sprache zu nennen hilft nur bei YouTrack.
  if ATemplate.Provider = TAtlasTrackerTarget.GitHub then
    Exit;
  if ATemplate.Language = TAtlasTrackerTemplates.German then
    Result := Result + ' (' + TAtlasStrings.Text(TAtlasTextId.TrackerLanguageGerman) + ')'
  else
    Result := Result + ' (' + TAtlasStrings.Text(TAtlasTextId.TrackerLanguageEnglish) + ')';
end;

procedure TAtlasTrackerQueryDialog.FillTemplates;
var
  mCaptions: TArray<string>;
  mTemplate: TAtlasTrackerTemplate;
begin
  FTemplates := TemplatesFor(FConnections, FConnection.Choice);
  mCaptions := TArray<string>.Create(TAtlasStrings.Text(TAtlasTextId.QueryDialogTemplatePick));
  for mTemplate in FTemplates do
    mCaptions := mCaptions + [TemplateCaption(mTemplate)];
  FTemplate.SetChoices(mCaptions);
  FTemplate.Choice := 0;
end;

function TAtlasTrackerQueryDialog.Query: TAtlasTrackerQuery;
var
  mChoice: Integer;
  mConnection: string;
begin
  mChoice := FConnection.Choice;
  mConnection := '';
  if (mChoice >= 1) and (mChoice <= Length(FConnections)) then
    mConnection := FConnections[mChoice - 1].Name
  else if mChoice > Length(FConnections) then
    // Verbindung, die es nicht mehr gibt: unverändert lassen.
    mConnection := FMissingConnection;
  Result := TAtlasTrackerQuery.Create(FName.Text, FQuery.Text, mConnection, FProject.Text);
end;

function TAtlasTrackerQueryDialog.TestConnection(out AConnection: TAtlasTrackerConnection): Boolean;
var
  mChoice: Integer;
begin
  mChoice := FConnection.Choice;
  Result := Length(FConnections) > 0;
  if not Result then
    Exit;
  if (mChoice >= 1) and (mChoice <= Length(FConnections)) then
    AConnection := FConnections[mChoice - 1]
  else if mChoice = 0 then
    // „(alle)“: getestet wird über die erste Verbindung.
    AConnection := FConnections[0]
  else
    Result := False;
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
    if SameText(mName, mQuery.Name) then
      mTaken := True;
  FOk.Enabled := (mQuery.Name <> '') and not mTaken and (mQuery.Query <> '');
  FTest.Enabled := not FTesting and Assigned(FOnTest) and TestConnection(mConnection);
  if mTaken then
    FResult.Text := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesQueryNameTaken);
end;

procedure TAtlasTrackerQueryDialog.ConnectionChange(Sender: TObject);
begin
  FillTemplates;
  Changed(Sender);
end;

procedure TAtlasTrackerQueryDialog.SelectConnection(AChoice: Integer);
begin
  FConnection.Choice := AChoice;
  ConnectionChange(FConnection);
end;

procedure TAtlasTrackerQueryDialog.TemplateChange(Sender: TObject);
begin
  ApplyTemplate(FTemplate.Choice - 1);
end;

procedure TAtlasTrackerQueryDialog.ApplyTemplate(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FTemplates)) then
    Exit;
  FQuery.Text := FTemplates[AIndex].Query;
  // Zurück auf „(Vorlage einsetzen …)“, damit dieselbe Vorlage noch einmal wählbar bleibt.
  FTemplate.Choice := 0;
  Changed(FTemplate);
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
    Exit;
  mQuery := Query;
  // Wie in „Meine Issues“: Projekt aus dem Feld, Abfrage leer = Vorgabe in der Sprache der Verbindung.
  mTarget := TAtlasTrackerTarget.Create(mConnection.Provider, mConnection.Url, mQuery.Project, mQuery.Query);
  mTarget.Language := mConnection.Language;
  FTesting := True;
  FResult.Text := TAtlasStrings.Text(TAtlasTextId.QueryDialogTesting);
  Changed(Sender);
  mLinkRef := FLinkRef;
  mLink := FLink;
  mName := mConnection.Name;
  FOnTest(mConnection, mTarget,
    procedure(const AResult: TAtlasTrackerQueryTestResult)
    begin
      if (mLinkRef <> nil) and (mLink.Dialog <> nil) then
        mLink.Dialog.ShowResult(AResult, mName);
    end);
end;

procedure TAtlasTrackerQueryDialog.ShowResult(const AResult: TAtlasTrackerQueryTestResult;
  const AConnectionName: string);
begin
  FTesting := False;
  FResult.Text := ResultText(AResult, AConnectionName);
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
        mLines := [TAtlasStrings.Fmt(TAtlasTextId.QueryTestFoundMore, [AResult.Count, AResult.ElapsedMs,
          string.Join(', ', AResult.Keys)])]
      else
        mLines := [TAtlasStrings.Fmt(TAtlasTextId.QueryTestFound, [AResult.Count, AResult.ElapsedMs,
          string.Join(', ', AResult.Keys)])];
    TAtlasTrackerQueryOutcome.Empty:
      mLines := [TAtlasStrings.Fmt(TAtlasTextId.QueryTestEmpty, [AResult.ElapsedMs])];
    TAtlasTrackerQueryOutcome.NoToken:
      mLines := [TAtlasStrings.Text(TAtlasTextId.QueryTestNoToken)];
    TAtlasTrackerQueryOutcome.NotConfigured:
      mLines := [TAtlasStrings.Text(TAtlasTextId.QueryTestNotConfigured)];
    TAtlasTrackerQueryOutcome.Rejected:
      mLines := [TAtlasStrings.Fmt(TAtlasTextId.QueryTestRejected, [AResult.HttpStatus])];
    TAtlasTrackerQueryOutcome.ProjectUnknown:
      mLines := [TAtlasStrings.Text(TAtlasTextId.QueryTestProjectUnknown)];
    TAtlasTrackerQueryOutcome.QueryRejected:
      mLines := [TAtlasStrings.Fmt(TAtlasTextId.QueryTestQueryRejected, [AResult.HttpStatus,
        AResult.TrackerMessage])];
    TAtlasTrackerQueryOutcome.Unreadable:
      mLines := [TAtlasStrings.Fmt(TAtlasTextId.QueryTestUnreadable, [AResult.HttpStatus])];
    TAtlasTrackerQueryOutcome.ServerError:
      mLines := [TAtlasStrings.Fmt(TAtlasTextId.QueryTestServerError, [AResult.HttpStatus])];
  else
    mLines := [TAtlasStrings.Text(TAtlasTextId.QueryTestUnreachable)];
  end;
  if AResult.SuggestedQuery <> '' then
    mLines := mLines + [TAtlasStrings.Fmt(TAtlasTextId.QueryTestTipGerman, [AResult.SuggestedQuery])];
  if AResult.SentQuery <> '' then
    mLines := mLines + [TAtlasStrings.Fmt(TAtlasTextId.QueryTestSent, [AConnectionName, AResult.SentQuery])];
  Result := string.Join(sLineBreak, mLines);
end;

procedure TAtlasTrackerQueryDialog.OkClick(Sender: TObject);
begin
  if not FOk.Enabled then
    Exit;
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
      AQuery := mDialog.Query;
  finally
    mDialog.Free;
  end;
end;

end.
