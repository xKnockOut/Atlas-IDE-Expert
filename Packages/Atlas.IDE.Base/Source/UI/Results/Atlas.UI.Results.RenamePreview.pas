unit Atlas.UI.Results.RenamePreview;

// Vorschau vor dem Umbenennen (#400), reine VCL: alle betroffenen Zeilen
// nach Unit gruppiert, je Zeile vorher und nachher („alt  →  neu“). Erst
// „Umbenennen“ übernimmt die Änderungen; Doppelklick zeigt die Stelle im
// Editor, ohne den Dialog zu schließen. Andere Befehle mit WorkspaceEdit
// (Eigenschaftsregeln anwenden, #309) nennen ihren eigenen Knopf.
// Nennt der Server erschlossene Stellen, die er nicht ändert (#1119), stehen
// sie unter „Nicht geändert, bitte prüfen“, die Änderungen unter „Wird geändert“.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Atlas.Core.Results.Model,
  Atlas.UI.Results.View;

type
  TAtlasRenamePreview = class
  public
    /// <summary>True, wenn der Benutzer „Umbenennen“ wählt. AOnOpen zeigt eine Stelle (darf nil sein).</summary>
    class function Execute(const ATitle, AHint: string; const AGroups: TArray<TAtlasResultGroup>;
      const AOnOpen: TAtlasResultsOpen): Boolean; overload; static;
    /// <summary>Wie oben mit eigener Beschriftung AApply für den Knopf, der übernimmt.</summary>
    class function Execute(const ATitle, AHint, AApply: string; const AGroups: TArray<TAtlasResultGroup>;
      const AOnOpen: TAtlasResultsOpen): Boolean; overload; static;
  end;

implementation

uses
  Atlas.UI.Results.Frame,
  Atlas.UI.Results.Strings;

/// <summary>Knöpfe unten rechts: „Abbrechen“ und AApply; liefert den Knopf, der übernimmt.</summary>
function AddButtons(ADialog: TForm; const AApply: string): TButton;
var
  mButtons: TPanel;
  mCancel: TButton;
begin
  mButtons := TPanel.Create(ADialog);
  mButtons.Parent := ADialog;
  mButtons.Align := alBottom;
  mButtons.Height := ADialog.ScaleValue(44);
  mButtons.BevelOuter := bvNone;
  mCancel := TButton.Create(ADialog);
  mCancel.Parent := mButtons;
  mCancel.Caption := TAtlasResultsStrings.Text(TAtlasResultsTextId.RenamePreviewCancel);
  mCancel.ModalResult := mrCancel;
  mCancel.Cancel := True;
  mCancel.Width := ADialog.ScaleValue(100);
  mCancel.Top := ADialog.ScaleValue(9);
  mCancel.Left := mButtons.ClientWidth - mCancel.Width - ADialog.ScaleValue(10);
  mCancel.Anchors := [akTop, akRight];
  Result := TButton.Create(ADialog);
  Result.Parent := mButtons;
  Result.Caption := AApply;
  Result.ModalResult := mrOk;
  Result.Default := True;
  Result.Width := mCancel.Width;
  Result.Top := mCancel.Top;
  Result.Left := mCancel.Left - Result.Width - ADialog.ScaleValue(8);
  Result.Anchors := [akTop, akRight];
end;

/// <summary>Stellen nach Unit; mit erschlossenen Stellen getrennt nach „Wird geändert“ und „Nicht geändert“.</summary>
procedure ShowGroups(AResults: TAtlasResultsFrame; const AHint: string; const AGroups: TArray<TAtlasResultGroup>);
var
  mGroup: TAtlasResultGroup;
  mEntries: TArray<TAtlasResultEntry>;
begin
  mEntries := nil;
  for mGroup in AGroups do
  begin
    mEntries := mEntries + mGroup.Entries;
  end;
  if TAtlasResults.InferredCount(mEntries) > 0 then
  begin
    AResults.Entries.ShowRated(AHint, mEntries, TAtlasResultsStrings.Text(TAtlasResultsTextId.RenameChangedGroup),
      TAtlasResultsStrings.Text(TAtlasResultsTextId.RenameUnchangedGroup));
  end
  else
  begin
    AResults.Entries.Show(AHint, AGroups);
  end;
end;

class function TAtlasRenamePreview.Execute(const ATitle, AHint: string; const AGroups: TArray<TAtlasResultGroup>;
  const AOnOpen: TAtlasResultsOpen): Boolean;
begin
  Result := Execute(ATitle, AHint, TAtlasResultsStrings.Text(TAtlasResultsTextId.RenamePreviewApply), AGroups, AOnOpen);
end;

class function TAtlasRenamePreview.Execute(const ATitle, AHint, AApply: string;
  const AGroups: TArray<TAtlasResultGroup>; const AOnOpen: TAtlasResultsOpen): Boolean;
var
  mDialog: TForm;
  mResults: TAtlasResultsFrame;
  mApply: TButton;
begin
  mDialog := TForm.CreateNew(nil);
  try
    mDialog.Caption := ATitle;
    mDialog.BorderStyle := bsSizeable;
    mDialog.BorderIcons := [biSystemMenu];
    mDialog.Position := poMainFormCenter;
    mDialog.Width := mDialog.ScaleValue(720);
    mDialog.Height := mDialog.ScaleValue(480);
    mApply := AddButtons(mDialog, AApply);
    mResults := TAtlasResultsFrame.Create(mDialog);
    mResults.Parent := mDialog;
    mResults.Align := alClient;
    mResults.OnOpen := AOnOpen;
    ShowGroups(mResults, AHint, AGroups);
    mDialog.ActiveControl := mApply;
    Result := mDialog.ShowModal = mrOk;
  finally
    mDialog.Free;
  end;
end;

end.
