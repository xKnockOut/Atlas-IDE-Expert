unit Atlas.Core.Debug.ExceptionDialog;

// Den Exception-Dialog der IDE erkennen (#517, #783), ohne VCL und Open Tools
// API. Die Open Tools API meldet beim Halt wegen einer Exception weder Klasse
// noch Meldung (IOTAThreadNotifier.ThreadNotify nur nrException). Der Dialog
// der IDE („Project X.exe raised exception class … with message '…'.“) hat
// beides. Die IDE-Schicht sammelt die Texte und Knöpfe eines sichtbaren
// Dialogs, solange der Prozess wegen einer Exception steht; hier fällt die
// Entscheidung:
//   - Recognize: Ist es der Exception-Dialog (ein Text mit Klasse), und welche
//     Knöpfe sind „Anhalten“ und „Fortsetzen“?
//   - Captions ohne „&“ vergleichen; Deutsch und Englisch.
// Welche Fensterklasse der Dialog je IDE-Version hat und ob die Knöpfe so
// heißen, klärt die Studie aus #783 (docs/Studie-Exception-Dialog.md); bis
// dahin gilt der Dialog nur als erkannt, wenn Text und beide Knöpfe passen.

interface

type
  {$SCOPEDENUMS ON}
  TAtlasDebugDialogButton = (Other, BreakButton, ContinueButton);
  {$SCOPEDENUMS OFF}

  TAtlasDebugDialogScan = record
    /// <summary>Text des Dialogs mit der Exception; '' wenn keiner passt.</summary>
    Text: string;
    ExceptionClass: string;
    Message: string;
    /// <summary>Index des Knopfs „Anhalten“ bzw. „Fortsetzen“ in den übergebenen Knöpfen; -1 ohne.</summary>
    BreakIndex: Integer;
    ContinueIndex: Integer;
    /// <summary>Text mit Klasse gefunden.</summary>
    function HasException: Boolean;
    /// <summary>Exception-Dialog mit beiden Knöpfen: Atlas darf ihn mit „Fortsetzen“ schließen.</summary>
    function CanContinue: Boolean;
  end;

  TAtlasDebugExceptionDialog = record
  public
    /// <summary>Art eines Knopfs nach seiner Beschriftung.</summary>
    class function ButtonKind(const ACaption: string): TAtlasDebugDialogButton; static;
    /// <summary>Texte (Beschriftungen, Felder) und Knöpfe eines Fensters auswerten.</summary>
    class function Recognize(const ATexts, AButtons: TArray<string>): TAtlasDebugDialogScan; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.Exceptions;

function Plain(const ACaption: string): string;
begin
  Result := Trim(StringReplace(ACaption, '&', '', [rfReplaceAll]));
  // „Fortsetzen (F9)“ und ähnliche Zusätze.
  if Pos('(', Result) > 1 then
  begin
    Result := Trim(Copy(Result, 1, Pos('(', Result) - 1));
  end;
end;

{ TAtlasDebugDialogScan }

function TAtlasDebugDialogScan.HasException: Boolean;
begin
  Result := ExceptionClass <> '';
end;

function TAtlasDebugDialogScan.CanContinue: Boolean;
begin
  Result := HasException and (BreakIndex >= 0) and (ContinueIndex >= 0);
end;

{ TAtlasDebugExceptionDialog }

class function TAtlasDebugExceptionDialog.ButtonKind(const ACaption: string): TAtlasDebugDialogButton;
const
  cBreakWords: array[0..2] of string = ('Break', 'Anhalten', 'Unterbrechen');
  cContinueWords: array[0..1] of string = ('Continue', 'Fortsetzen');
var
  mCaption, mWord: string;
begin
  mCaption := Plain(ACaption);
  for mWord in cBreakWords do
  begin
    if SameText(mCaption, mWord) then
    begin
      Exit(TAtlasDebugDialogButton.BreakButton);
    end;
  end;
  for mWord in cContinueWords do
  begin
    if SameText(mCaption, mWord) then
    begin
      Exit(TAtlasDebugDialogButton.ContinueButton);
    end;
  end;
  Result := TAtlasDebugDialogButton.Other;
end;

class function TAtlasDebugExceptionDialog.Recognize(const ATexts, AButtons: TArray<string>): TAtlasDebugDialogScan;
var
  mText, mExceptionClass, mMessage: string;
  mIndex: Integer;
begin
  Result := Default(TAtlasDebugDialogScan);
  Result.BreakIndex := -1;
  Result.ContinueIndex := -1;
  for mText in ATexts do
  begin
    // Nur Texte, die wie die Meldung der IDE aussehen: mit Klasse und mit Projekt bzw. Prozess davor.
    if TAtlasDebugExceptionText.Parse(mText, mExceptionClass, mMessage) and
      ((Pos('raised', LowerCase(mText)) > 0) or (Pos('aufgetreten', LowerCase(mText)) > 0) or
       (Pos('ausgelöst', LowerCase(mText)) > 0)) then
    begin
      Result.Text := mText;
      Result.ExceptionClass := mExceptionClass;
      Result.Message := mMessage;
      Break;
    end;
  end;
  for mIndex := 0 to High(AButtons) do
    case ButtonKind(AButtons[mIndex]) of
      TAtlasDebugDialogButton.BreakButton:
        if Result.BreakIndex < 0 then
        begin
          Result.BreakIndex := mIndex;
        end;
      TAtlasDebugDialogButton.ContinueButton:
        if Result.ContinueIndex < 0 then
        begin
          Result.ContinueIndex := mIndex;
        end;
    end;
end;

end.
