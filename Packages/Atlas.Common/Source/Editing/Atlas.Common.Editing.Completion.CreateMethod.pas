unit Atlas.Common.Editing.Completion.CreateMethod;

// Quelle der Vervollständigung für „Methode aus Aufruf anlegen“ (#472): Nach "(" (Auslöser des Plugins) gibt es nur
// dieses Angebot oder nichts, mit Strg+Leer auf dem Namen eines Aufrufs steht es oben in der Liste. Die Stelle des
// Aufrufs erkennt Atlas.Common.Editing.CreateMethod; Kopf und Änderungen liefert die Komposition (sie kennt den
// Kontext der Refactorings). Läuft an TCompletionSlot.CreateMethod.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Completion.Request,
  Atlas.Common.Completion.Answer;

type
  /// <summary>Titel, Kopf und Änderungen für den Aufruf am Cursor; False ohne Angebot (bekannter Name, kein Aufruf,
  /// abgeschaltet).</summary>
  TEditingCreateMethodFunc = reference to function(ARequest: TCompletionRequest; out ATitle, ADetail: string;
    out AEdits: TArray<TTextEdit>): Boolean;

  TEditingCreateMethodCompletion = class
  public
    /// <summary>Quelle für TCompletionSlot.CreateMethod über ACreateFor.</summary>
    class function Source(const ACreateFor: TEditingCreateMethodFunc): TCompletionSource; static;
  end;

implementation

uses
  Atlas.Common.Completion.Contract,
  Atlas.Common.Editing.CreateMethod;

/// <summary>Der Eintrag: Nach dem Auslöser "(" bleibt der Text an der Aufrufstelle, mit Strg+Leer auf dem Namen
/// ersetzt der Eintrag ihn durch sich selbst. Die Deklaration kommt als Zusatzänderung.</summary>
function CreateItem(ARequest: TCompletionRequest; const ACreateFor: TEditingCreateMethodFunc;
  out AItem: TCompletionItem): Boolean;
var
  mSite: TCreateCallSite;
  mTitle, mDetail: string;
  mEdits: TArray<TTextEdit>;
begin
  AItem := Default(TCompletionItem);
  Result := (ARequest.Tree <> nil) and TCreateMethod.Site(ARequest.Tree.Tokens, ARequest.Position, mSite) and
    ACreateFor(ARequest, mTitle, mDetail, mEdits);
  if not Result then
  begin
    Exit;
  end;
  AItem.Name := mTitle;
  AItem.Kind := cKindMethod;
  AItem.Detail := mDetail;
  AItem.Fits := True;
  AItem.Pinned := True;
  AItem.Action := 'create';
  AItem.Unknown := mSite.Name;
  AItem.HasTextEdit := True;
  AItem.TextEdit := TTextEdit.Create(mSite.NameRange, mSite.Name);
  if ARequest.Trigger = '(' then
  begin
    AItem.TextEdit := TTextEdit.Create(TTextRange.Create(ARequest.Position, ARequest.Position), '');
  end;
  AItem.AdditionalEdits := mEdits;
end;

{ TEditingCreateMethodCompletion }

class function TEditingCreateMethodCompletion.Source(const ACreateFor: TEditingCreateMethodFunc):
  TCompletionSource;
begin
  Result :=
    function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome
    var
      Item: TCompletionItem;
      Found: Boolean;
    begin
      Result := TCompletionOutcome.Next;
      Found := Assigned(ACreateFor) and CreateItem(ARequest, ACreateFor, Item);
      if ARequest.Trigger = '(' then
      begin
        AAnswer.Exclusive := Default(TCompletionItems);
        if Found then
        begin
          AAnswer.Exclusive.Items := [Item];
        end;
        Result := TCompletionOutcome.Answered;
      end
      else if Found then
      begin
        AAnswer.Hints := AAnswer.Hints + [Item];
      end;
    end;
end;

end.
