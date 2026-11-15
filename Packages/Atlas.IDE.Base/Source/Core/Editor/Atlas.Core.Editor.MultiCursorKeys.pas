unit Atlas.Core.Editor.MultiCursorKeys;

// Tasten und Klicks bei mehreren Einfügemarken (#589), ohne Open Tools API und VCL.
// - Solange Zusatzmarken bestehen, fängt Atlas nur die Tasten der Tabelle ab: Esc, Rücktaste, Entf, Enter,
//   Pfeile, Pos1/Ende, Kopieren, Ausschneiden, Einfügen. Bei Regeln ohne Exact erweitert Umschalt die
//   Markierung (Umschalt+→), bei Regeln mit Exact gelten genau die angegebenen Umschalttasten.
// - Strg+K, dann die Taste fürs Überspringen (editor.multiCursorSkipKey, 0 = aus); jede andere Taste nach
//   Strg+K wirkt normal.
// - Zeichen außerhalb der Grundebene kommen als zwei WM_CHAR: Das hohe Surrogat wartet auf das tiefe.
// - Ein Klick setzt bzw. entfernt eine Marke nur mit genau der eingestellten Taste (Alt, sonst Strg).

{$SCOPEDENUMS ON}

interface

uses
  System.Classes,
  Atlas.Core.Editor.MultiCursor;

type
  /// <summary>Was eine Taste an allen Marken auslöst.</summary>
  TAtlasMultiCursorKeyAction = (None, Finish, Skip, Chord, Backspace, Delete, NewLine, Cut, Copy, Paste, Move);

  /// <summary>Ergebnis einer Taste: Action None, wenn sie der IDE bleibt.</summary>
  TAtlasMultiCursorKeyCommand = record
    Action: TAtlasMultiCursorKeyAction;
    Move: TAtlasCaretMove;
    /// <summary>Umschalt gedrückt: Bewegung erweitert die Markierung.</summary>
    Extend: Boolean;
  end;

  TAtlasMultiCursorKeys = record
  public const
    cKeyBack = $08;
    cKeyReturn = $0D;
    cKeyEscape = $1B;
    cKeyEnd = $23;
    cKeyHome = $24;
    cKeyLeft = $25;
    cKeyUp = $26;
    cKeyRight = $27;
    cKeyDown = $28;
    cKeyInsert = $2D;
    cKeyDelete = $2E;
    /// <summary>Kennzeichen eines Kürzels wie TShortCut der VCL.</summary>
    cShortCutShift = $2000;
    cShortCutCtrl = $4000;
    cShortCutAlt = $8000;
  public
    /// <summary>Regel für AKey mit AShift; Action None, wenn die Taste der IDE bleibt.</summary>
    class function Command(AKey: Word; AShift: TShiftState): TAtlasMultiCursorKeyCommand; static;
    /// <summary>Strg+K, dann ASkipKey (Kürzel wie TShortCut, 0 = aus): Skip, Chord oder None. AChord merkt sich,
    /// ob Strg+K zuletzt kam.</summary>
    class function Chord(var AChord: Boolean; AKey: Word; AShift: TShiftState; ASkipKey: Integer):
      TAtlasMultiCursorKeyAction; static;
    /// <summary>Kürzel aus Taste und Umschalttasten, wie ShortCut der VCL.</summary>
    class function ShortCutOf(AKey: Word; AShift: TShiftState): Integer; static;
    /// <summary>Hohes Surrogat wartet in AHigh (False); sonst steht in AText, was einzufügen ist.</summary>
    class function Compose(var AHigh: Char; ATyped: Char; out AText: string): Boolean; static;
    /// <summary>Steuerzeichen (Strg+Buchstabe, Rücktaste, Enter, Tab, Entf), die als WM_CHAR nichts einfügen.
    /// </summary>
    class function IsControlChar(ATyped: Char): Boolean; static;
    /// <summary>Setzt ein Klick mit AShift eine Marke? Nur mit genau Strg (ACtrl, editor.multiCursorModifier)
    /// bzw. Alt und wenn Atlas und die Marken an sind (AEnabled).</summary>
    class function ClickWanted(AShift: TShiftState; ACtrl, AEnabled: Boolean): Boolean; static;
  end;

implementation

type
  /// <summary>Tastenregel: Key mit Mods (Exact: genau diese Umschalttasten, sonst erweitert Umschalt die
  /// Markierung) löst Action aus.</summary>
  TKeyRule = record
    Key: Word;
    Mods: TShiftState;
    Exact: Boolean;
    Action: TAtlasMultiCursorKeyAction;
    Move: TAtlasCaretMove;
  end;

const
  // Tasten, die Atlas abfängt, solange Zusatzmarken bestehen; alle anderen gehen an die IDE.
  cKeyRules: array[0..17] of TKeyRule = (
    (Key: TAtlasMultiCursorKeys.cKeyEscape; Mods: []; Exact: True; Action: TAtlasMultiCursorKeyAction.Finish;
      Move: TAtlasCaretMove.Left),
    (Key: TAtlasMultiCursorKeys.cKeyBack; Mods: []; Exact: False; Action: TAtlasMultiCursorKeyAction.Backspace;
      Move: TAtlasCaretMove.Left),
    (Key: TAtlasMultiCursorKeys.cKeyDelete; Mods: []; Exact: True; Action: TAtlasMultiCursorKeyAction.Delete;
      Move: TAtlasCaretMove.Left),
    (Key: TAtlasMultiCursorKeys.cKeyDelete; Mods: [ssShift]; Exact: True; Action: TAtlasMultiCursorKeyAction.Cut;
      Move: TAtlasCaretMove.Left),
    (Key: TAtlasMultiCursorKeys.cKeyReturn; Mods: []; Exact: False; Action: TAtlasMultiCursorKeyAction.NewLine;
      Move: TAtlasCaretMove.Left),
    (Key: TAtlasMultiCursorKeys.cKeyLeft; Mods: []; Exact: False; Action: TAtlasMultiCursorKeyAction.Move;
      Move: TAtlasCaretMove.Left),
    (Key: TAtlasMultiCursorKeys.cKeyLeft; Mods: [ssCtrl]; Exact: False; Action: TAtlasMultiCursorKeyAction.Move;
      Move: TAtlasCaretMove.WordLeft),
    (Key: TAtlasMultiCursorKeys.cKeyRight; Mods: []; Exact: False; Action: TAtlasMultiCursorKeyAction.Move;
      Move: TAtlasCaretMove.Right),
    (Key: TAtlasMultiCursorKeys.cKeyRight; Mods: [ssCtrl]; Exact: False; Action: TAtlasMultiCursorKeyAction.Move;
      Move: TAtlasCaretMove.WordRight),
    (Key: TAtlasMultiCursorKeys.cKeyUp; Mods: []; Exact: False; Action: TAtlasMultiCursorKeyAction.Move;
      Move: TAtlasCaretMove.Up),
    (Key: TAtlasMultiCursorKeys.cKeyDown; Mods: []; Exact: False; Action: TAtlasMultiCursorKeyAction.Move;
      Move: TAtlasCaretMove.Down),
    (Key: TAtlasMultiCursorKeys.cKeyHome; Mods: []; Exact: False; Action: TAtlasMultiCursorKeyAction.Move;
      Move: TAtlasCaretMove.LineStart),
    (Key: TAtlasMultiCursorKeys.cKeyEnd; Mods: []; Exact: False; Action: TAtlasMultiCursorKeyAction.Move;
      Move: TAtlasCaretMove.LineEnd),
    (Key: TAtlasMultiCursorKeys.cKeyInsert; Mods: [ssCtrl]; Exact: True; Action: TAtlasMultiCursorKeyAction.Copy;
      Move: TAtlasCaretMove.Left),
    (Key: TAtlasMultiCursorKeys.cKeyInsert; Mods: [ssShift]; Exact: True; Action: TAtlasMultiCursorKeyAction.Paste;
      Move: TAtlasCaretMove.Left),
    (Key: Ord('C'); Mods: [ssCtrl]; Exact: True; Action: TAtlasMultiCursorKeyAction.Copy;
      Move: TAtlasCaretMove.Left),
    (Key: Ord('X'); Mods: [ssCtrl]; Exact: True; Action: TAtlasMultiCursorKeyAction.Cut;
      Move: TAtlasCaretMove.Left),
    (Key: Ord('V'); Mods: [ssCtrl]; Exact: True; Action: TAtlasMultiCursorKeyAction.Paste;
      Move: TAtlasCaretMove.Left));

{ TAtlasMultiCursorKeys }

class function TAtlasMultiCursorKeys.Command(AKey: Word; AShift: TShiftState): TAtlasMultiCursorKeyCommand;
var
  mRule: TKeyRule;
  mMods: TShiftState;
begin
  Result := Default(TAtlasMultiCursorKeyCommand);
  for mRule in cKeyRules do
  begin
    mMods := AShift * [ssCtrl, ssAlt];
    if mRule.Exact then
    begin
      mMods := AShift * [ssShift, ssCtrl, ssAlt];
    end;
    if (mRule.Key = AKey) and (mMods = mRule.Mods) then
    begin
      Result.Action := mRule.Action;
      Result.Move := mRule.Move;
      Result.Extend := ssShift in AShift;
      Exit;
    end;
  end;
end;

class function TAtlasMultiCursorKeys.Chord(var AChord: Boolean; AKey: Word; AShift: TShiftState;
  ASkipKey: Integer): TAtlasMultiCursorKeyAction;
begin
  Result := TAtlasMultiCursorKeyAction.None;
  if ASkipKey = 0 then
  begin
    AChord := False;
    Exit;
  end;
  if AChord and (ShortCutOf(AKey, AShift) = ASkipKey) then
  begin
    Result := TAtlasMultiCursorKeyAction.Skip;
  end
  else if (AKey = Ord('K')) and (AShift * [ssShift, ssCtrl, ssAlt] = [ssCtrl]) then
  begin
    Result := TAtlasMultiCursorKeyAction.Chord;
  end;
  AChord := Result = TAtlasMultiCursorKeyAction.Chord;
end;

class function TAtlasMultiCursorKeys.ShortCutOf(AKey: Word; AShift: TShiftState): Integer;
begin
  Result := 0;
  if Hi(AKey) <> 0 then
  begin
    Exit;
  end;
  Result := AKey;
  if ssShift in AShift then
  begin
    Inc(Result, cShortCutShift);
  end;
  if ssCtrl in AShift then
  begin
    Inc(Result, cShortCutCtrl);
  end;
  if ssAlt in AShift then
  begin
    Inc(Result, cShortCutAlt);
  end;
end;

class function TAtlasMultiCursorKeys.Compose(var AHigh: Char; ATyped: Char; out AText: string): Boolean;
begin
  AText := ATyped;
  Result := (ATyped < #$D800) or (ATyped > #$DBFF);
  if not Result then
  begin
    AHigh := ATyped;
    Exit;
  end;
  if (AHigh <> #0) and (ATyped >= #$DC00) and (ATyped <= #$DFFF) then
  begin
    AText := AHigh + ATyped;
  end;
  AHigh := #0;
end;

class function TAtlasMultiCursorKeys.IsControlChar(ATyped: Char): Boolean;
begin
  Result := (ATyped < ' ') or (ATyped = #127);
end;

class function TAtlasMultiCursorKeys.ClickWanted(AShift: TShiftState; ACtrl, AEnabled: Boolean): Boolean;
var
  mWanted: TShiftState;
begin
  mWanted := [ssAlt];
  if ACtrl then
  begin
    mWanted := [ssCtrl];
  end;
  Result := AEnabled and (AShift * [ssShift, ssCtrl, ssAlt] = mWanted);
end;

end.
