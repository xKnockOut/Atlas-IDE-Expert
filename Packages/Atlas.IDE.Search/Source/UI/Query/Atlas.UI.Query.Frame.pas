unit Atlas.UI.Query.Frame;

// Inhalt des Fensters „Atlas-Abfrage“ (#1351), reine VCL:
// - oben die Auswahl gespeicherter Abfragen (queries aus atlas.json; Wahl
//   setzt die Abfrage ein und führt sie aus), „Ausführen“, „Abbrechen“,
//   „Als Regel speichern …“ und „Als CSV kopieren“,
// - darunter die Eingabezeile mit Vervollständigung: Mengen, Felder,
//   Prädikate, Schlüsselwörter und @name aus dem Katalog des Servers
//   (TAtlasQueryCompletion), hinter inherits, implements, uses, calls und has
//   attribute Symbolnamen über OnSymbols. Die Liste erscheint beim Tippen und
//   mit Strg+Leer; Pfeile wählen, Enter oder Tab übernimmt, Esc schließt.
//   Enter ohne Liste führt aus. Ein Fehler steht unter der Zeile mit Spalte
//   und Vorschlag, die Schreibmarke springt an die Spalte.
// - die Ergebnisliste mit einer Spalte je Feld der Antwort und „Datei“
//   (Pfad:Zeile, erschlossene Treffer mit Vermerk). Klick auf eine Spalte
//   sortiert (nochmals: umgekehrt; bei Gleichstand eindeutig nach Pfad,
//   Zeile, Spalte), Doppelklick oder Enter springt zur Deklaration
//   (OnOpenLocation, Zeile und Spalte ab 1). Die Liste ist virtuell
//   (OwnerData), auch viele Zeilen füllen sofort.
// - unten die Statuszeile mit Treffern, Laufzeit und erschlossenen Treffern
//   bzw. einem Hinweis.
// - „Hilfe“: Aufbau einer Abfrage, Beispiele und die Mengen mit ihren Feldern
//   aus dem Katalog des Servers; steht an der Stelle der Liste, solange kein
//   Ergebnis da ist, und lässt sich über den Knopf ein- und ausblenden.
// Die IDE-Schicht bettet den Frame in ein andockbares Fenster ein, fragt den
// Server und ruft SetCatalog, SetAnswer, SetRunning bzw. SetMessage. Die DFM
// ist leer (TCustomFrame.Create verlangt eine Ressource); aufgebaut wird im
// Code, gefüllt erst mit Fenster (CreateWnd).
// Die Teile (Leiste, Eingabezeile, Ergebnisliste, Ereignisse) stehen in
// Atlas.UI.Query.Parts; der Frame verbindet sie mit Hilfe und Statuszeile.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.Forms,
  Atlas.Core.Query.Model,
  Atlas.UI.Query.Parts;

type
  TAtlasCodeQuerySymbols = Atlas.UI.Query.Parts.TAtlasCodeQuerySymbols;

  TAtlasCodeQueryFrame = class(TFrame)
  private
    FEvents: TAtlasCodeQueryEvents;
    FToolbar: TAtlasQueryToolbar;
    FInputBar: TAtlasQueryInput;
    FResults: TAtlasQueryResults;
    /// <summary>Hilfe an der Stelle der Liste: Aufbau, Beispiele, Mengen und Felder aus dem Katalog.</summary>
    FHelp: TMemo;
    /// <summary>Wahl über den Knopf: 0 automatisch (Hilfe, solange kein Ergebnis da ist), 1 gezeigt, -1 verborgen.
    /// </summary>
    FHelpChoice: Integer;
    FStatus: TLabel;
    FRunning: Boolean;
    FMessageText: string;
    procedure UpdateButtons;
    /// <summary>Hilfe zeigen, solange kein Ergebnis da ist oder sie eingeschaltet ist; Text aus dem Katalog.</summary>
    procedure UpdateHelp;
    procedure UpdateStatus;
    procedure HelpClick(Sender: TObject);
    procedure SavedChange(Sender: TObject);
    procedure RunClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    procedure SaveRuleClick(Sender: TObject);
    procedure CopyCsvClick(Sender: TObject);
    procedure InputEdited(Sender: TObject);
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Katalog des Servers (Vervollständigung, gespeicherte Abfragen).</summary>
    procedure SetCatalog(const ACatalog: TAtlasQueryCatalog);
    /// <summary>Antwort zeigen; die gewählte Sortierung bleibt.</summary>
    procedure SetAnswer(const AAnswer: TAtlasQueryAnswer);
    /// <summary>Abfrage läuft: „Abbrechen“ an, „Ausführen“ aus, Hinweis in der Statuszeile.</summary>
    procedure SetRunning(ARunning: Boolean);
    /// <summary>Hinweis in der Statuszeile (kein Projekt, kein Server, abgebrochen …); AKeep: bisherige Treffer
    /// stehen lassen.</summary>
    procedure SetMessage(const AText: string; AKeep: Boolean);
    /// <summary>Abfrage ausführen (OnRun mit dem Text der Eingabezeile); nichts bei leerer Zeile.</summary>
    procedure Run;
    /// <summary>Ereignisse für die IDE-Schicht.</summary>
    property Events: TAtlasCodeQueryEvents read FEvents;
    property Toolbar: TAtlasQueryToolbar read FToolbar;
    property InputBar: TAtlasQueryInput read FInputBar;
    property ResultList: TAtlasQueryResults read FResults;
    property HelpMemo: TMemo read FHelp;
    property StatusLabel: TLabel read FStatus;
    property Running: Boolean read FRunning;
  end;

implementation

uses
  Vcl.Clipbrd,
  Atlas.UI.Search.Strings;

{$R *.dfm}

{ TAtlasCodeQueryFrame }

constructor TAtlasCodeQueryFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  // Als erste Komponente angelegt, wird sie nach den Teilen freigegeben, die die Ereignisse rufen.
  FEvents := TAtlasCodeQueryEvents.Create(Self);

  FToolbar := TAtlasQueryToolbar.Create(Self);
  FToolbar.SavedCombo.OnChange := SavedChange;
  FToolbar.RunButton.OnClick := RunClick;
  FToolbar.CancelButton.OnClick := CancelClick;
  FToolbar.SaveRuleButton.OnClick := SaveRuleClick;
  FToolbar.CopyCsvButton.OnClick := CopyCsvClick;
  FToolbar.HelpButton.OnClick := HelpClick;

  FInputBar := TAtlasQueryInput.Create(Self, FEvents);
  FInputBar.Top := FToolbar.Top + FToolbar.Height + 1;
  FInputBar.OnSubmit := RunClick;
  FInputBar.OnEdited := InputEdited;

  FStatus := TLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.Align := alBottom;
  FStatus.AlignWithMargins := True;
  FStatus.ShowAccelChar := False;

  FResults := TAtlasQueryResults.Create(Self, FEvents);

  FHelp := TMemo.Create(Self);
  FHelp.Parent := Self;
  FHelp.Align := alClient;
  FHelp.AlignWithMargins := True;
  FHelp.ReadOnly := True;
  FHelp.WordWrap := True;
  FHelp.ScrollBars := ssVertical;
  FHelp.BorderStyle := bsNone;
  FHelp.TabStop := False;
  FHelp.Visible := False;

  UpdateButtons;
end;

procedure TAtlasCodeQueryFrame.CreateWnd;
begin
  inherited CreateWnd;
  // Auswahl und Liste halten ihre Einträge im Fenster: erst jetzt füllen.
  FToolbar.FillSaved(FInputBar.Catalog);
  FResults.FillColumns;
  FResults.FillRows;
  UpdateStatus;
  UpdateHelp;
end;

procedure TAtlasCodeQueryFrame.SetCatalog(const ACatalog: TAtlasQueryCatalog);
begin
  FInputBar.Catalog := ACatalog;
  FToolbar.FillSaved(ACatalog);
  UpdateHelp;
end;

/// <summary>Zeile der Hilfe zu einer Menge: Name, Titel, Felder und Prädikate.</summary>
function EntityHelp(const AEntity: TAtlasQueryEntity): string;
var
  mField: TAtlasQueryField;
  mNames: TArray<string>;
begin
  mNames := nil;
  for mField in AEntity.Fields do
  begin
    mNames := mNames + [mField.Name];
  end;
  for mField in AEntity.Predicates do
  begin
    mNames := mNames + [mField.Name];
  end;
  Result := '  ' + AEntity.Name;
  if AEntity.Caption <> '' then
  begin
    Result := Result + ' (' + AEntity.Caption + ')';
  end;
  if mNames <> nil then
  begin
    Result := Result + ': ' + string.Join(', ', mNames);
  end;
end;

/// <summary>Text der Hilfe: Aufbau und Beispiele, dazu die Mengen aus dem Katalog des Servers (stimmt immer mit der
/// Sprache überein).</summary>
function HelpText(const ACatalog: TAtlasQueryCatalog): string;
var
  mEntity: TAtlasQueryEntity;
begin
  Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.QueryHelpIntro);
  if ACatalog.Entities = nil then
  begin
    Exit;
  end;
  Result := Result + sLineBreak + sLineBreak + TAtlasSearchStrings.Text(TAtlasSearchTextId.QueryHelpEntities);
  for mEntity in ACatalog.Entities do
  begin
    Result := Result + sLineBreak + EntityHelp(mEntity);
  end;
end;

procedure TAtlasCodeQueryFrame.UpdateHelp;
begin
  FHelp.Text := HelpText(FInputBar.Catalog);
  // Ohne Ergebnis steht die Hilfe an der Stelle der leeren Liste; der Knopf blendet sie ein und aus.
  if FHelpChoice = 0 then
  begin
    FHelp.Visible := not FResults.HasAnswer;
  end
  else
  begin
    FHelp.Visible := FHelpChoice > 0;
  end;
  FResults.Visible := not FHelp.Visible;
end;

procedure TAtlasCodeQueryFrame.HelpClick(Sender: TObject);
begin
  if FHelp.Visible then
  begin
    FHelpChoice := -1;
  end
  else
  begin
    FHelpChoice := 1;
  end;
  UpdateHelp;
end;

procedure TAtlasCodeQueryFrame.SetAnswer(const AAnswer: TAtlasQueryAnswer);
begin
  FRunning := False;
  FMessageText := '';
  FHelpChoice := 0;
  FResults.SetAnswer(AAnswer);
  FInputBar.ShowError(FResults.Answer, True);
  UpdateButtons;
  UpdateStatus;
  UpdateHelp;
end;

procedure TAtlasCodeQueryFrame.SetRunning(ARunning: Boolean);
begin
  FRunning := ARunning;
  if ARunning then
  begin
    FMessageText := TAtlasSearchStrings.Text(TAtlasSearchTextId.QueryRunning);
  end;
  UpdateButtons;
  UpdateStatus;
end;

procedure TAtlasCodeQueryFrame.SetMessage(const AText: string; AKeep: Boolean);
begin
  FMessageText := AText;
  FRunning := False;
  if not AKeep then
  begin
    FHelpChoice := 0;
    FResults.ClearAnswer;
    FInputBar.ShowError(FResults.Answer, False);
  end;
  UpdateButtons;
  UpdateStatus;
  UpdateHelp;
end;

procedure TAtlasCodeQueryFrame.UpdateButtons;
begin
  FToolbar.RunButton.Enabled := not FRunning;
  FToolbar.CancelButton.Enabled := FRunning;
  FToolbar.SaveRuleButton.Enabled := Trim(FInputBar.Edit.Text) <> '';
  FToolbar.CopyCsvButton.Enabled := FResults.HasAnswer and (Length(FResults.Answer.Rows) > 0);
end;

/// <summary>Statuszeile zu einer Antwort: Treffer, Laufzeit, erschlossene Treffer.</summary>
function AnswerStatus(const AAnswer: TAtlasQueryAnswer): string;
begin
  if Length(AAnswer.Rows) = 0 then
  begin
    Exit(TAtlasSearchStrings.Text(TAtlasSearchTextId.QueryEmpty));
  end;
  if AAnswer.Truncated then
  begin
    Result := TAtlasSearchStrings.Fmt(TAtlasSearchTextId.QueryStatusTruncated, [Length(AAnswer.Rows), AAnswer.Total,
      AAnswer.ElapsedMs]);
  end
  else
  begin
    Result := TAtlasSearchStrings.Fmt(TAtlasSearchTextId.QueryStatus, [AAnswer.Total, AAnswer.ElapsedMs]);
  end;
  if AAnswer.InferredCount > 0 then
  begin
    Result := Result + TAtlasSearchStrings.Fmt(TAtlasSearchTextId.QueryStatusInferred, [AAnswer.InferredCount]);
  end;
end;

procedure TAtlasCodeQueryFrame.UpdateStatus;
begin
  if FMessageText <> '' then
  begin
    FStatus.Caption := FMessageText;
  end
  else if not FResults.HasAnswer or FResults.Answer.Failed then
  begin
    FStatus.Caption := '';
  end
  else
  begin
    FStatus.Caption := AnswerStatus(FResults.Answer);
  end;
end;

procedure TAtlasCodeQueryFrame.Run;
var
  mText: string;
begin
  FInputBar.HideSuggest;
  mText := Trim(FInputBar.Edit.Text);
  if (mText <> '') and not FRunning and Assigned(FEvents.OnRun) then
  begin
    FEvents.OnRun(mText);
  end;
end;

procedure TAtlasCodeQueryFrame.SavedChange(Sender: TObject);
var
  mIndex: Integer;
begin
  mIndex := FToolbar.SavedCombo.ItemIndex - 1;
  if (mIndex < 0) or (mIndex > High(FInputBar.Catalog.Saved)) then
  begin
    Exit;
  end;
  FInputBar.ReplaceText(FInputBar.Catalog.Saved[mIndex].Query);
  UpdateButtons;
  Run;
end;

procedure TAtlasCodeQueryFrame.RunClick(Sender: TObject);
begin
  Run;
end;

procedure TAtlasCodeQueryFrame.CancelClick(Sender: TObject);
begin
  if FRunning and Assigned(FEvents.OnCancel) then
  begin
    FEvents.OnCancel();
  end;
end;

procedure TAtlasCodeQueryFrame.SaveRuleClick(Sender: TObject);
begin
  FInputBar.HideSuggest;
  if (Trim(FInputBar.Edit.Text) <> '') and Assigned(FEvents.OnSaveRule) then
  begin
    FEvents.OnSaveRule(Trim(FInputBar.Edit.Text));
  end;
end;

procedure TAtlasCodeQueryFrame.CopyCsvClick(Sender: TObject);
var
  mCount: Integer;
begin
  mCount := Length(FResults.Answer.Rows);
  if not FResults.HasAnswer or (mCount = 0) then
  begin
    Exit;
  end;
  Clipboard.AsText := FResults.CsvText;
  FMessageText := TAtlasSearchStrings.Fmt(TAtlasSearchTextId.QueryCopied, [mCount]);
  UpdateStatus;
  if Assigned(FEvents.OnCopied) then
  begin
    FEvents.OnCopied(mCount);
  end;
end;

procedure TAtlasCodeQueryFrame.InputEdited(Sender: TObject);
begin
  UpdateButtons;
end;

end.
