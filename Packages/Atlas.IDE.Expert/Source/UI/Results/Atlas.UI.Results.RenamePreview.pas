unit Atlas.UI.Results.RenamePreview;

// Vorschau vor dem Umbenennen (#400), reine VCL: alle betroffenen Zeilen
// nach Unit gruppiert, je Zeile vorher und nachher („alt  →  neu“). Erst
// „Umbenennen“ übernimmt die Änderungen; Doppelklick zeigt die Stelle im
// Editor, ohne den Dialog zu schließen.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Atlas.Core.Results.Model,
  Atlas.UI.Results.Frame;

type
  TAtlasRenamePreview = class
  public
    /// <summary>True, wenn der Benutzer „Umbenennen“ wählt. AOnOpen zeigt eine Stelle (darf nil sein).</summary>
    class function Execute(const ATitle, AHint: string; const AGroups: TArray<TAtlasResultGroup>;
      const AOnOpen: TAtlasResultsOpen): Boolean; static;
  end;

implementation

uses
  Atlas.UI.Strings;

class function TAtlasRenamePreview.Execute(const ATitle, AHint: string; const AGroups: TArray<TAtlasResultGroup>;
  const AOnOpen: TAtlasResultsOpen): Boolean;
var
  Dialog: TForm;
  Results: TAtlasResultsFrame;
  Buttons: TPanel;
  Apply, Cancel: TButton;
begin
  Dialog := TForm.CreateNew(nil);
  try
    Dialog.Caption := ATitle;
    Dialog.BorderStyle := bsSizeable;
    Dialog.BorderIcons := [biSystemMenu];
    Dialog.Position := poMainFormCenter;
    Dialog.Width := Dialog.ScaleValue(720);
    Dialog.Height := Dialog.ScaleValue(480);
    Buttons := TPanel.Create(Dialog);
    Buttons.Parent := Dialog;
    Buttons.Align := alBottom;
    Buttons.Height := Dialog.ScaleValue(44);
    Buttons.BevelOuter := bvNone;
    Cancel := TButton.Create(Dialog);
    Cancel.Parent := Buttons;
    Cancel.Caption := TAtlasStrings.Text(TAtlasTextId.RenamePreviewCancel);
    Cancel.ModalResult := mrCancel;
    Cancel.Cancel := True;
    Cancel.Width := Dialog.ScaleValue(100);
    Cancel.Top := Dialog.ScaleValue(9);
    Cancel.Left := Buttons.ClientWidth - Cancel.Width - Dialog.ScaleValue(10);
    Cancel.Anchors := [akTop, akRight];
    Apply := TButton.Create(Dialog);
    Apply.Parent := Buttons;
    Apply.Caption := TAtlasStrings.Text(TAtlasTextId.RenamePreviewApply);
    Apply.ModalResult := mrOk;
    Apply.Default := True;
    Apply.Width := Cancel.Width;
    Apply.Top := Cancel.Top;
    Apply.Left := Cancel.Left - Apply.Width - Dialog.ScaleValue(8);
    Apply.Anchors := [akTop, akRight];
    Results := TAtlasResultsFrame.Create(Dialog);
    Results.Parent := Dialog;
    Results.Align := alClient;
    Results.OnOpen := AOnOpen;
    Results.ShowEntries(AHint, AGroups);
    Dialog.ActiveControl := Apply;
    Result := Dialog.ShowModal = mrOk;
  finally
    Dialog.Free;
  end;
end;

end.
