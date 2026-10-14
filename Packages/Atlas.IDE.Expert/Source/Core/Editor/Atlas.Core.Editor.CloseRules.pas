unit Atlas.Core.Editor.CloseRules;

// Schließlogik der Atlas-Fenster (#414, ARG-009) ohne IDE und ohne VCL:
//
// | Ereignis                          | Popup    | Parameter-Hint                     | Tooltip           |
// |-----------------------------------|----------|------------------------------------|-------------------|
// | Esc                               | schließt | schließt (wenn kein Popup offen)   | schließt          |
// | Übernahme eines Eintrags          | schließt | bleibt bzw. öffnet (#429)          | –                 |
// | Cursor verlässt Wort bzw. Aufruf  | schließt | schließt                           | schließt          |
// | Fokus weg, IDE inaktiv            | schließt | schließt                           | schließt          |
// | Editor scrollt                    | schließt | wandert mit, schließt außer Sicht  | schließt          |
// | Größe ändert sich, Tab-Wechsel    | schließt | schließt                           | schließt          |
// | Maus verlässt Bezeichner und Tip  | –        | –                                  | nach 300 ms       |
//
// Die Editor-Units lesen den Zustand (Application.Active, GetFocus, TopRow …)
// und fragen hier, ob und warum geschlossen wird. Esc und Übernahme regeln
// der Controller der Vervollständigung und die Tastenreihenfolge (#410).

interface

uses
  System.Types;

{$SCOPEDENUMS ON}

type
  TAtlasCloseReason = (None, Inactive, FocusLost, OtherFile, Resized, Scrolled, OutOfView, OtherLine, BeforeWord,
    NonIdentifier);

  /// <summary>Was die Editor-Units beim Öffnen und bei jeder Prüfung ablesen.</summary>
  TAtlasEditorWindowState = record
    /// <summary>Die IDE ist die aktive Anwendung.</summary>
    AppActive: Boolean;
    /// <summary>Fenster mit dem Fokus (HWND als Zahl), 0 ohne.</summary>
    Focus: NativeUInt;
    FileName: string;
    /// <summary>Oberste sichtbare Zeile, ab 1 wie TOTAEditView.TopRow.</summary>
    TopRow: Integer;
    /// <summary>Sichtbare Zeilen.</summary>
    Rows: Integer;
    Size: TPoint;
  end;

  TAtlasCloseRules = record
  public const
    /// <summary>So lange bleibt der Tooltip, nachdem die Maus Bezeichner und Tooltip verlassen hat.</summary>
    TooltipHideDelayMs = 300;
  private
    class function Window(const AOpened, ANow: TAtlasEditorWindowState): TAtlasCloseReason; static;
  public
    /// <summary>Popup der Vervollständigung: IDE inaktiv, Fokus, Tab, Größe, Scrollen.</summary>
    class function Popup(const AOpened, ANow: TAtlasEditorWindowState): TAtlasCloseReason; static;
    /// <summary>Wort verlassen: andere Zeile, Cursor vor dem Wortanfang oder ein Zeichen, das kein Bezeichner ist.
    /// AWordStart und ACharacter 0-basiert; AIndex ist dann die Stelle des Zeichens (1-basiert in ALineText).
    /// </summary>
    class function PopupWord(ALineSame: Boolean; const ALineText: string; AWordStart, ACharacter: Integer;
      out AIndex: Integer): TAtlasCloseReason; static;
    /// <summary>Verzögertes Öffnen der Liste (ARG-046): Nach der Wartezeit öffnet sie nur, wenn das Fenster
    /// unverändert ist und seit dem Auslösen an ACharacterAtStart nur Bezeichnerzeichen getippt wurden.</summary>
    class function DelayedOpen(const AOpened, ANow: TAtlasEditorWindowState; ALineSame: Boolean;
      const ALineText: string; ACharacterAtStart, ACharacter: Integer): Boolean; static;
    /// <summary>Parameter-Hint. Gescrollt mit sichtbarer Ankerzeile (Zeile der Klammer beim Öffnen, ab 1) ist
    /// kein Grund: Der Hint wandert dann mit (AMove).</summary>
    class function Hint(const AOpened, ANow: TAtlasEditorWindowState; AAnchorLine: Integer;
      out AMove: Boolean): TAtlasCloseReason; static;
    /// <summary>Tooltip. Angeheftet oder mit der Maus darüber bleibt er bei Fokus- und Tab-Wechsel, nicht aber,
    /// wenn die IDE inaktiv wird.</summary>
    class function Tooltip(const AOpened, ANow: TAtlasEditorWindowState; APinned, AMouseOver: Boolean)
      : TAtlasCloseReason; static;
    /// <summary>Für das Protokoll.</summary>
    class function Name(AReason: TAtlasCloseReason): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Completion.Word;

{ TAtlasCloseRules }

class function TAtlasCloseRules.Window(const AOpened, ANow: TAtlasEditorWindowState): TAtlasCloseReason;
begin
  Result := TAtlasCloseReason.None;
  if not ANow.AppActive then
    Result := TAtlasCloseReason.Inactive
  else if ANow.Focus <> AOpened.Focus then
    Result := TAtlasCloseReason.FocusLost
  else if not SameText(ANow.FileName, AOpened.FileName) then
    Result := TAtlasCloseReason.OtherFile
  else if ANow.Size <> AOpened.Size then
    Result := TAtlasCloseReason.Resized;
end;

class function TAtlasCloseRules.Popup(const AOpened, ANow: TAtlasEditorWindowState): TAtlasCloseReason;
begin
  Result := Window(AOpened, ANow);
  if (Result = TAtlasCloseReason.None) and (ANow.TopRow <> AOpened.TopRow) then
    Result := TAtlasCloseReason.Scrolled;
end;

class function TAtlasCloseRules.PopupWord(ALineSame: Boolean; const ALineText: string; AWordStart,
  ACharacter: Integer; out AIndex: Integer): TAtlasCloseReason;
var
  Index: Integer;
begin
  AIndex := 0;
  if not ALineSame then
    Exit(TAtlasCloseReason.OtherLine);
  if ACharacter < AWordStart then
    Exit(TAtlasCloseReason.BeforeWord);
  for Index := AWordStart + 1 to ACharacter do
    if (Index > Length(ALineText)) or not TAtlasWord.IsIdentifierChar(ALineText[Index]) then
    begin
      AIndex := Index;
      Exit(TAtlasCloseReason.NonIdentifier);
    end;
  Result := TAtlasCloseReason.None;
end;

class function TAtlasCloseRules.DelayedOpen(const AOpened, ANow: TAtlasEditorWindowState; ALineSame: Boolean;
  const ALineText: string; ACharacterAtStart, ACharacter: Integer): Boolean;
var
  Index: Integer;
begin
  Result := (Popup(AOpened, ANow) = TAtlasCloseReason.None) and
    (PopupWord(ALineSame, ALineText, ACharacterAtStart, ACharacter, Index) = TAtlasCloseReason.None);
end;

class function TAtlasCloseRules.Hint(const AOpened, ANow: TAtlasEditorWindowState; AAnchorLine: Integer;
  out AMove: Boolean): TAtlasCloseReason;
begin
  AMove := False;
  Result := Window(AOpened, ANow);
  if (Result <> TAtlasCloseReason.None) or (ANow.TopRow = AOpened.TopRow) then
    Exit;
  // Die Klammer, an der der Hint hängt, entscheidet, nicht der Caret.
  if (AAnchorLine < ANow.TopRow) or (AAnchorLine >= ANow.TopRow + ANow.Rows) then
    Result := TAtlasCloseReason.OutOfView
  else
    AMove := True;
end;

class function TAtlasCloseRules.Tooltip(const AOpened, ANow: TAtlasEditorWindowState; APinned,
  AMouseOver: Boolean): TAtlasCloseReason;
begin
  Result := Window(AOpened, ANow);
  if (Result = TAtlasCloseReason.None) and (ANow.TopRow <> AOpened.TopRow) then
    Result := TAtlasCloseReason.Scrolled;
  // Angeheftet oder mit der Maus darüber: Fokus- und Tab-Wechsel lassen ihn stehen.
  if (APinned or AMouseOver) and (Result in [TAtlasCloseReason.FocusLost, TAtlasCloseReason.OtherFile]) then
    Result := TAtlasCloseReason.None;
end;

class function TAtlasCloseRules.Name(AReason: TAtlasCloseReason): string;
const
  Names: array[TAtlasCloseReason] of string = ('keiner', 'IDE inaktiv', 'Fokus woanders', 'anderer Tab',
    'Größe geändert', 'gescrollt', 'außer Sicht', 'andere Zeile', 'Cursor vor dem Wortanfang',
    'Zeichen getippt');
begin
  Result := Names[AReason];
end;

end.
