unit Atlas.Core.Debug.DialogInput;

// Entscheidungen der Vervollständigung in den Debugger-Dialogen (#538), ohne IDE prüfbar (#1967): Beschriftung
// eines Felds über die Lage der Labels, ganz markierter Text, Mitgliederliste nach „.“, was nach einer Eingabe mit
// einer offenen Liste geschieht, welche Tasten Atlas übernimmt und welcher Bereich beim Übernehmen ersetzt wird.
// Fenster, Nachrichten und Tastencodes bleiben in Atlas.IDE.Debug.DialogCompletion.

interface

uses
  System.Types;

{$SCOPEDENUMS ON}

type
  /// <summary>Sichtbares Label im Container des Felds: Beschriftung und Lage.</summary>
  TAtlasDialogLabel = record
    Caption: string;
    Bounds: TRect;
    class function Create(const ACaption: string; const ABounds: TRect): TAtlasDialogLabel; static;
  end;

  /// <summary>Offene Liste nach einer Eingabe: schließen, neu fragen oder nur das Präfix nachführen.</summary>
  TAtlasDialogFollow = (Close, Query, UpdatePrefix);

  /// <summary>Zustand beim Druck einer Taste im verfolgten Feld.</summary>
  TAtlasDialogKeyInput = record
    /// <summary>Feld verfolgt, hat den Fokus und die Vervollständigung ist an.</summary>
    Tracked: Boolean;
    /// <summary>Leertaste mit Strg (ohne weitere Umschalter).</summary>
    CtrlSpace: Boolean;
    /// <summary>Ohne Umschalttasten.</summary>
    Plain: Boolean;
    /// <summary>Taste bewegt bzw. bestätigt in der Liste.</summary>
    Navigation: Boolean;
    /// <summary>Pfeil nach unten.</summary>
    Down: Boolean;
    ListVisible: Boolean;
    ListActive: Boolean;
    /// <summary>Eingabefeld des Fensters „Auswerten“ mit eigenem Verlauf.</summary>
    OwnField: Boolean;
    FieldEmpty: Boolean;
  end;

  /// <summary>Auswahl im Feld beim Übernehmen: ersetzt wird SelStart bis SelStop, danach steht die Schreibmarke
  /// auf Caret.</summary>
  TAtlasDialogCommit = record
    SelStart: Integer;
    SelStop: Integer;
    Caret: Integer;
  end;

  TAtlasDialogInput = class
  public
    /// <summary>Abstand des Labels ABounds zum Feld AOwn: links in derselben Höhe oder direkt darüber; False sonst.
    /// </summary>
    class function LabelDistance(const ABounds, AOwn: TRect; out ADistance: Integer): Boolean; static;
    /// <summary>Beschriftung des nächsten Labels links bzw. über AOwn; '' ohne.</summary>
    class function NearestLabel(const ALabels: TArray<TAtlasDialogLabel>; const AOwn: TRect): string; static;
    /// <summary>Ist der ganze, nicht leere Text AText markiert (AStart bis AStop)?</summary>
    class function AllSelected(const AText: string; AStart, AStop: Integer): Boolean; static;
    /// <summary>Steht vor dem Wort APrefix an ACharacter in AText ein „.“ (Mitgliederliste, #497)?</summary>
    class function MemberTrigger(const AText: string; ACharacter: Integer; const APrefix: string): Boolean; static;
    /// <summary>Nach einer Eingabe bei offener Liste: Verlauf oder anderes Wort schließen, sonst neu fragen bzw.
    /// das Präfix nachführen.</summary>
    class function Follow(AHistoryMode, ASameWord, ANeedsQuery: Boolean): TAtlasDialogFollow; static;
    /// <summary>Übernimmt Atlas die Taste: Strg+Leertaste, Listentasten bei sichtbarer Liste, Pfeil nach unten im
    /// leeren Feld (Verlauf, #538; im Fenster „Auswerten“ zeigt das Fenster seinen eigenen).</summary>
    class function WantsKey(const AInput: TAtlasDialogKeyInput): Boolean; static;
    /// <summary>Bereich und Schreibmarke für AInsert: im Verlauf das ganze Feld, sonst das ganze Wort ab AWordStart
    /// an der Schreibmarke ACaret wie TAtlasExpressionEdit.Apply.</summary>
    class function Commit(const AText: string; ACaret, AWordStart: Integer; const AInsert: string;
      AHistoryMode: Boolean): TAtlasDialogCommit; static;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Debug.DialogCompletion;

const
  // So weit darf ein Label in das Feld hineinragen.
  cLabelOverlap = 4;

{ TAtlasDialogLabel }

class function TAtlasDialogLabel.Create(const ACaption: string; const ABounds: TRect): TAtlasDialogLabel;
begin
  Result.Caption := ACaption;
  Result.Bounds := ABounds;
end;

{ TAtlasDialogInput }

class function TAtlasDialogInput.LabelDistance(const ABounds, AOwn: TRect; out ADistance: Integer): Boolean;
begin
  Result := True;
  ADistance := 0;
  if (ABounds.Right <= AOwn.Left + cLabelOverlap) and (ABounds.Bottom > AOwn.Top) and (ABounds.Top < AOwn.Bottom) then
  begin
    ADistance := AOwn.Left - ABounds.Right;
  end
  else if (ABounds.Bottom <= AOwn.Top + cLabelOverlap) and (ABounds.Left < AOwn.Right) and
    (ABounds.Right > AOwn.Left) then
  begin
    ADistance := AOwn.Top - ABounds.Bottom;
  end
  else
  begin
    Result := False;
  end;
end;

class function TAtlasDialogInput.NearestLabel(const ALabels: TArray<TAtlasDialogLabel>; const AOwn: TRect): string;
var
  mLabel: TAtlasDialogLabel;
  mDistance, mBest: Integer;
begin
  Result := '';
  mBest := MaxInt;
  for mLabel in ALabels do
  begin
    if LabelDistance(mLabel.Bounds, AOwn, mDistance) and (mDistance < mBest) then
    begin
      mBest := mDistance;
      Result := mLabel.Caption;
    end;
  end;
end;

class function TAtlasDialogInput.AllSelected(const AText: string; AStart, AStop: Integer): Boolean;
begin
  Result := (AText <> '') and (AStart = 0) and (AStop = Length(AText));
end;

class function TAtlasDialogInput.MemberTrigger(const AText: string; ACharacter: Integer;
  const APrefix: string): Boolean;
var
  mWordStart: Integer;
begin
  // Zeichen vor dem Wortanfang, 1-basiert an der Stelle des Wortanfangs.
  mWordStart := ACharacter - Length(APrefix);
  Result := (mWordStart > 0) and (mWordStart <= Length(AText)) and (AText[mWordStart] = '.');
end;

class function TAtlasDialogInput.Follow(AHistoryMode, ASameWord, ANeedsQuery: Boolean): TAtlasDialogFollow;
begin
  if AHistoryMode or not ASameWord then
  begin
    Result := TAtlasDialogFollow.Close;
  end
  else if ANeedsQuery then
  begin
    Result := TAtlasDialogFollow.Query;
  end
  else
  begin
    Result := TAtlasDialogFollow.UpdatePrefix;
  end;
end;

class function TAtlasDialogInput.WantsKey(const AInput: TAtlasDialogKeyInput): Boolean;
begin
  if not AInput.Tracked then
  begin
    Result := False;
  end
  else if AInput.CtrlSpace then
  begin
    Result := True;
  end
  else if not AInput.Plain then
  begin
    Result := False;
  end
  else if AInput.ListVisible and AInput.Navigation then
  begin
    Result := True;
  end
  else
  begin
    Result := AInput.Down and not AInput.OwnField and not AInput.ListActive and AInput.FieldEmpty;
  end;
end;

class function TAtlasDialogInput.Commit(const AText: string; ACaret, AWordStart: Integer; const AInsert: string;
  AHistoryMode: Boolean): TAtlasDialogCommit;
var
  mText: string;
begin
  if AHistoryMode then
  begin
    Result.SelStart := 0;
    Result.SelStop := -1;
    Result.Caret := Length(AInsert);
    Exit;
  end;
  TAtlasExpressionEdit.Apply(AText, ACaret, ACaret - Max(AWordStart, 0), AInsert, mText, Result.Caret);
  Result.SelStart := Max(AWordStart, 0);
  Result.SelStop := Length(AText) - (Length(mText) - Result.Caret);
end;

end.
