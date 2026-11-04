unit Atlas.UI.Updates.Offer;

// Angebot eines Updates (#1519, Mockup 2): „Jetzt aktualisieren“ fragt, ob
// Atlas das Update im Hintergrund vorbereiten und beim Schließen der IDE
// installieren soll. Bei einer neuen Hauptversion steht ein Hinweis auf die
// Änderungen dabei. Ist das Update schon vorbereitet, bietet derselbe Weg
// die Auswahl der Module und „Nicht installieren“ an.

interface

type
{$SCOPEDENUMS ON}
  TAtlasUpdateOfferAnswer = (Later, Install, Changes);
  TAtlasUpdateReadyAnswer = (Close, Modules, Discard);
{$SCOPEDENUMS OFF}

  TAtlasUpdateOffer = class
  public
    /// <summary>Update AVersion anbieten; AMajor: neue Hauptversion.</summary>
    class function Offer(const AVersion, AInstalled: string; AMajor: Boolean): TAtlasUpdateOfferAnswer; static;
    /// <summary>Vorbereitetes Update; AModules: Module wählbar.</summary>
    class function Ready(const AVersion: string; AModules: Boolean): TAtlasUpdateReadyAnswer; static;
  end;

implementation

uses
  Vcl.Dialogs,
  Atlas.UI.Updates.Strings;

const
  cAnswerBase = 100;

procedure AddButton(ADialog: TTaskDialog; AId: TAtlasUpdatesTextId; AResult: Integer; ADefault: Boolean);
var
  mButton: TTaskDialogBaseButtonItem;
begin
  mButton := ADialog.Buttons.Add;
  mButton.Caption := TAtlasUpdatesStrings.Text(AId);
  mButton.ModalResult := cAnswerBase + AResult;
  mButton.Default := ADefault;
end;

function NewDialog(const ATitle: string): TTaskDialog;
begin
  Result := TTaskDialog.Create(nil);
  Result.Caption := 'Atlas';
  Result.Title := ATitle;
  Result.CommonButtons := [];
  Result.Flags := [tfAllowDialogCancellation];
end;

/// <summary>Gewählte Antwort ab 0; Abbrechen (Esc, Kreuz) = 0.</summary>
function Answer(ADialog: TTaskDialog): Integer;
begin
  Result := 0;
  if ADialog.Execute and (ADialog.ModalResult >= cAnswerBase) then
  begin
    Result := ADialog.ModalResult - cAnswerBase;
  end;
end;

{ TAtlasUpdateOffer }

class function TAtlasUpdateOffer.Offer(const AVersion, AInstalled: string; AMajor: Boolean): TAtlasUpdateOfferAnswer;
var
  mDialog: TTaskDialog;
begin
  mDialog := NewDialog(TAtlasUpdatesStrings.Fmt(TAtlasUpdatesTextId.UpdatesOfferTitle, [AVersion]));
  try
    mDialog.Text := TAtlasUpdatesStrings.Fmt(TAtlasUpdatesTextId.UpdatesOfferText, [AInstalled]);
    if AMajor then
    begin
      mDialog.Text := mDialog.Text + sLineBreak + sLineBreak +
        TAtlasUpdatesStrings.Text(TAtlasUpdatesTextId.UpdatesOfferMajor);
    end;
    AddButton(mDialog, TAtlasUpdatesTextId.UpdatesOfferInstall, Ord(TAtlasUpdateOfferAnswer.Install), not AMajor);
    AddButton(mDialog, TAtlasUpdatesTextId.UpdatesOfferChanges, Ord(TAtlasUpdateOfferAnswer.Changes), AMajor);
    AddButton(mDialog, TAtlasUpdatesTextId.UpdatesOfferLater, Ord(TAtlasUpdateOfferAnswer.Later), False);
    Result := TAtlasUpdateOfferAnswer(Answer(mDialog));
  finally
    mDialog.Free;
  end;
end;

class function TAtlasUpdateOffer.Ready(const AVersion: string; AModules: Boolean): TAtlasUpdateReadyAnswer;
var
  mDialog: TTaskDialog;
begin
  mDialog := NewDialog(TAtlasUpdatesStrings.Fmt(TAtlasUpdatesTextId.UpdatesReadyText, [AVersion]));
  try
    if AModules then
    begin
      AddButton(mDialog, TAtlasUpdatesTextId.UpdatesReadyModules, Ord(TAtlasUpdateReadyAnswer.Modules), True);
    end;
    AddButton(mDialog, TAtlasUpdatesTextId.UpdatesReadyDiscard, Ord(TAtlasUpdateReadyAnswer.Discard), False);
    AddButton(mDialog, TAtlasUpdatesTextId.UpdatesOfferLater, Ord(TAtlasUpdateReadyAnswer.Close), not AModules);
    Result := TAtlasUpdateReadyAnswer(Answer(mDialog));
  finally
    mDialog.Free;
  end;
end;

end.
