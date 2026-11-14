unit Shell.Monitor.CheckOptions;

// Host-Rolle Shell von AtlasMonitor (#1900): Spalte „Optionen“ des Reiters „Prüfen“ mit Befehl, Schwere, Regeln,
// Profil, Auswahl der Dateien, Baseline und den Werten einzelner Befehle (Sammelkorrektur, Abfrage, Architektur-
// Stand, Absturzfall) sowie dem Editor für Doppelklick. Liest und schreibt TMonitorCheckState; die Befehle und ihre
// Schalter stehen in TMonitorCommands.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Atlas.Common.Monitor.Commands,
  Atlas.Common.Monitor.Targets;

type
  {$SCOPEDENUMS ON}
  TMonitorField = (Rules, Profile, Units, ChangedBase, DiffRef, Baseline, FixRules, AffectedBase, Query,
    ArchitectureFile, ReplayFile, Editor);
  TMonitorFlag = (Changed, IncludeUncommitted, ChangedLines, UpdateBaseline, NoIndex, Timings);
  {$SCOPEDENUMS OFF}

  TMonitorCheckOptions = class(TComponent)
  private
    FBox: TScrollBox;
    FTop: Integer;
    FCommandBox: TComboBox;
    FSeverityBox: TComboBox;
    FEdits: array[TMonitorField] of TEdit;
    FChecks: array[TMonitorFlag] of TCheckBox;
    FActive: Boolean;
    function AddLabel(const ACaption: string): TLabel;
    function AddCombo(const ACaption: string): TComboBox;
    procedure AddEdit(AField: TMonitorField; const ACaption: string);
    procedure AddCheck(AFlag: TMonitorFlag; const ACaption: string);
    procedure BuildFields;
    procedure FillCombos;
  public
    /// <summary>Legt die Spalte links in AParent an.</summary>
    constructor Create(AOwner: TComponent; AParent: TWinControl); reintroduce;
    /// <summary>Füllt die Auswahllisten; erst mit Fenster (CreateWnd des Formulars).</summary>
    procedure Activate(const AState: TMonitorCheckState);
    /// <summary>Werte aus den Feldern in AState (Befehl, Optionen, Editor); vor Activate unverändert.</summary>
    procedure Store(var AState: TMonitorCheckState);
    /// <summary>Beschriftung eines Felds für Hinweise („Bitte zuerst … angeben“).</summary>
    function FieldCaption(AField: TMonitorField): string;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.Common.Monitor.Texts;

const
  cWidth = 300;
  cGap = 6;
  cLabelHeight = 16;
  cEditHeight = 23;
  cCheckHeight = 22;
  cSeverities: array[0..4] of string = ('', 'error', 'warning', 'info', 'hint');

  cFieldTexts: array[TMonitorField] of TMonitorText = (TMonitorText.Rules, TMonitorText.Profile, TMonitorText.Units,
    TMonitorText.Changed, TMonitorText.DiffRef, TMonitorText.Baseline, TMonitorText.FixRules,
    TMonitorText.AffectedBase, TMonitorText.Query, TMonitorText.ArchitectureFile, TMonitorText.ReplayFile,
    TMonitorText.Editor);

/// <summary>AValue in Pixeln bei 96 dpi, umgerechnet auf die Auflösung des Bildschirms.</summary>
function Px(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, Screen.PixelsPerInch, 96);
end;

constructor TMonitorCheckOptions.Create(AOwner: TComponent; AParent: TWinControl);
begin
  inherited Create(AOwner);
  FBox := TScrollBox.Create(Self);
  FBox.Width := Px(cWidth + 3 * cGap + 20);
  FBox.Align := alLeft;
  FBox.VertScrollBar.Tracking := True;
  FBox.Parent := AParent;
  FTop := Px(cGap);
  BuildFields;
end;

function TMonitorCheckOptions.AddLabel(const ACaption: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Caption := ACaption;
  Result.SetBounds(Px(cGap), FTop, Px(cWidth), Px(cLabelHeight));
  Result.Parent := FBox;
  FTop := FTop + Px(cLabelHeight);
end;

function TMonitorCheckOptions.AddCombo(const ACaption: string): TComboBox;
begin
  AddLabel(ACaption);
  Result := TComboBox.Create(Self);
  Result.Style := csDropDownList;
  Result.SetBounds(Px(cGap), FTop, Px(cWidth), Px(cEditHeight));
  Result.Parent := FBox;
  FTop := FTop + Px(cEditHeight + cGap);
end;

procedure TMonitorCheckOptions.AddEdit(AField: TMonitorField; const ACaption: string);
begin
  if ACaption <> '' then
  begin
    AddLabel(ACaption);
  end;
  FEdits[AField] := TEdit.Create(Self);
  FEdits[AField].SetBounds(Px(cGap), FTop, Px(cWidth), Px(cEditHeight));
  FEdits[AField].Parent := FBox;
  FTop := FTop + Px(cEditHeight + cGap);
end;

procedure TMonitorCheckOptions.AddCheck(AFlag: TMonitorFlag; const ACaption: string);
begin
  FChecks[AFlag] := TCheckBox.Create(Self);
  FChecks[AFlag].Caption := ACaption;
  FChecks[AFlag].SetBounds(Px(cGap), FTop, Px(cWidth), Px(cCheckHeight));
  FChecks[AFlag].Parent := FBox;
  FTop := FTop + Px(cCheckHeight);
end;

function TMonitorCheckOptions.FieldCaption(AField: TMonitorField): string;
begin
  Result := TMonitorTexts.Text(cFieldTexts[AField]);
end;

procedure TMonitorCheckOptions.BuildFields;
var
  mField: TMonitorField;
begin
  FCommandBox := AddCombo(TMonitorTexts.Text(TMonitorText.Command));
  FSeverityBox := AddCombo(TMonitorTexts.Text(TMonitorText.Severity));
  for mField := TMonitorField.Rules to TMonitorField.Units do
  begin
    AddEdit(mField, FieldCaption(mField));
  end;
  AddCheck(TMonitorFlag.Changed, TMonitorTexts.Text(TMonitorText.Changed));
  AddEdit(TMonitorField.ChangedBase, '');
  AddEdit(TMonitorField.DiffRef, FieldCaption(TMonitorField.DiffRef));
  AddCheck(TMonitorFlag.IncludeUncommitted, TMonitorTexts.Text(TMonitorText.IncludeUncommitted));
  AddCheck(TMonitorFlag.ChangedLines, TMonitorTexts.Text(TMonitorText.ChangedLines));
  AddEdit(TMonitorField.Baseline, FieldCaption(TMonitorField.Baseline));
  AddCheck(TMonitorFlag.UpdateBaseline, TMonitorTexts.Text(TMonitorText.UpdateBaseline));
  AddCheck(TMonitorFlag.NoIndex, TMonitorTexts.Text(TMonitorText.NoIndex));
  AddCheck(TMonitorFlag.Timings, TMonitorTexts.Text(TMonitorText.Timings));
  FTop := FTop + Px(cGap);
  for mField := TMonitorField.FixRules to TMonitorField.Editor do
  begin
    AddEdit(mField, FieldCaption(mField));
  end;
  // Die Basis steht ohne eigene Beschriftung unter ihrem Haken; das Feld zeigt die Vorgabe als Hinweis.
  FEdits[TMonitorField.ChangedBase].TextHint := 'main';
  FEdits[TMonitorField.FixRules].TextHint := 'all';
end;

procedure TMonitorCheckOptions.FillCombos;
var
  mCommand: TMonitorCommand;
  I: Integer;
begin
  FCommandBox.Items.BeginUpdate;
  try
    FCommandBox.Items.Clear;
    for mCommand := Low(TMonitorCommand) to High(TMonitorCommand) do
    begin
      FCommandBox.Items.Add(TMonitorCommands.Text(mCommand));
    end;
  finally
    FCommandBox.Items.EndUpdate;
  end;
  FSeverityBox.Items.Clear;
  FSeverityBox.Items.Add(TMonitorTexts.Text(TMonitorText.SeverityAll));
  for I := 1 to High(cSeverities) do
  begin
    FSeverityBox.Items.Add(cSeverities[I]);
  end;
end;

procedure TMonitorCheckOptions.Activate(const AState: TMonitorCheckState);
var
  I: Integer;
begin
  FillCombos;
  FActive := True;
  FCommandBox.ItemIndex := Ord(AState.Command);
  FSeverityBox.ItemIndex := 0;
  for I := 1 to High(cSeverities) do
  begin
    if cSeverities[I] = AState.Options.MinSeverity then
    begin
      FSeverityBox.ItemIndex := I;
    end;
  end;
  FEdits[TMonitorField.Rules].Text := AState.Options.Rules;
  FEdits[TMonitorField.Profile].Text := AState.Options.Profile;
  FEdits[TMonitorField.Units].Text := AState.Options.Units;
  FEdits[TMonitorField.ChangedBase].Text := AState.Options.ChangedBase;
  FEdits[TMonitorField.DiffRef].Text := AState.Options.DiffRef;
  FEdits[TMonitorField.Baseline].Text := AState.Options.Baseline;
  FEdits[TMonitorField.FixRules].Text := AState.Options.FixRules;
  FEdits[TMonitorField.AffectedBase].Text := AState.Options.AffectedBase;
  FEdits[TMonitorField.Query].Text := AState.Options.Query;
  FEdits[TMonitorField.ArchitectureFile].Text := AState.Options.ArchitectureFile;
  FEdits[TMonitorField.ReplayFile].Text := AState.Options.ReplayFile;
  FEdits[TMonitorField.Editor].Text := AState.Editor;
  FChecks[TMonitorFlag.Changed].Checked := AState.Options.Changed;
  FChecks[TMonitorFlag.IncludeUncommitted].Checked := AState.Options.IncludeUncommitted;
  FChecks[TMonitorFlag.ChangedLines].Checked := AState.Options.ChangedLines;
  FChecks[TMonitorFlag.UpdateBaseline].Checked := AState.Options.UpdateBaseline;
  FChecks[TMonitorFlag.NoIndex].Checked := AState.Options.NoIndex;
  FChecks[TMonitorFlag.Timings].Checked := AState.Options.Timings;
end;

procedure TMonitorCheckOptions.Store(var AState: TMonitorCheckState);
begin
  // Vor Activate sind die Felder leer; der Stand bleibt dann, wie er war.
  if not FActive then
  begin
    Exit;
  end;
  if FCommandBox.ItemIndex >= 0 then
  begin
    AState.Command := TMonitorCommand(FCommandBox.ItemIndex);
  end;
  AState.Options.MinSeverity := '';
  if FSeverityBox.ItemIndex > 0 then
  begin
    AState.Options.MinSeverity := cSeverities[FSeverityBox.ItemIndex];
  end;
  AState.Options.Rules := Trim(FEdits[TMonitorField.Rules].Text);
  AState.Options.Profile := Trim(FEdits[TMonitorField.Profile].Text);
  AState.Options.Units := Trim(FEdits[TMonitorField.Units].Text);
  AState.Options.ChangedBase := Trim(FEdits[TMonitorField.ChangedBase].Text);
  AState.Options.DiffRef := Trim(FEdits[TMonitorField.DiffRef].Text);
  AState.Options.Baseline := Trim(FEdits[TMonitorField.Baseline].Text);
  AState.Options.FixRules := Trim(FEdits[TMonitorField.FixRules].Text);
  AState.Options.AffectedBase := Trim(FEdits[TMonitorField.AffectedBase].Text);
  AState.Options.Query := Trim(FEdits[TMonitorField.Query].Text);
  AState.Options.ArchitectureFile := Trim(FEdits[TMonitorField.ArchitectureFile].Text);
  AState.Options.ReplayFile := Trim(FEdits[TMonitorField.ReplayFile].Text);
  AState.Editor := Trim(FEdits[TMonitorField.Editor].Text);
  AState.Options.Changed := FChecks[TMonitorFlag.Changed].Checked;
  AState.Options.IncludeUncommitted := FChecks[TMonitorFlag.IncludeUncommitted].Checked;
  AState.Options.ChangedLines := FChecks[TMonitorFlag.ChangedLines].Checked;
  AState.Options.UpdateBaseline := FChecks[TMonitorFlag.UpdateBaseline].Checked;
  AState.Options.NoIndex := FChecks[TMonitorFlag.NoIndex].Checked;
  AState.Options.Timings := FChecks[TMonitorFlag.Timings].Checked;
end;

end.
