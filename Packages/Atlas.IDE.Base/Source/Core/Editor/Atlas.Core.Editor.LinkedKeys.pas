unit Atlas.Core.Editor.LinkedKeys;

// Tasten beim Mitziehen eines Bezeichners (#658), ohne Open Tools API und VCL: was eine Taste bzw. ein Zeichen in
// der Sitzung auslöst. Was die Taste aus dem Namen macht, rechnet Atlas.Core.Editor.LinkedEditing.
// - Mit Strg, Alt oder Umschalt (Wort löschen, Rückgängig …) arbeitet die IDE; Follow bzw. der Takt ziehen nach.
// - Esc beendet eine laufende Sitzung und stellt bei einem Konflikt den alten Namen wieder her; Enter beendet sie
//   ohne Zeilenumbruch. Rücktaste und Entf bearbeiten den Namen.
// - Zeichen eines Bezeichners bearbeiten den Namen; jedes andere Zeichen (Leerzeichen, Punkt, Klammer …) beendet
//   die Sitzung, das Zeichen schreibt die IDE. Zeichen außerhalb der Grundebene kommen als zwei WM_CHAR.

{$SCOPEDENUMS ON}

interface

type
  /// <summary>Was eine Taste (WM_KEYDOWN) auslöst.</summary>
  TAtlasLinkedKeyStep = (
    /// <summary>Taste geht unverändert an die IDE.</summary>
    Pass,
    /// <summary>Sitzung beenden, Taste verschlucken.</summary>
    Finish,
    /// <summary>Alten Namen wiederherstellen, dann beenden; Taste verschlucken.</summary>
    RestoreAndFinish,
    Backspace,
    Delete);

  /// <summary>Was ein Zeichen (WM_CHAR) auslöst.</summary>
  TAtlasLinkedCharStep = (
    /// <summary>Steuerzeichen: nichts tun.</summary>
    Ignore,
    /// <summary>Hohes Surrogat: auf das tiefe warten.</summary>
    HighSurrogate,
    /// <summary>Tiefes Surrogat zu einem wartenden hohen: das Paar einfügen.</summary>
    LowSurrogate,
    /// <summary>Zeichen eines Bezeichners: in den Namen schreiben.</summary>
    Insert,
    /// <summary>Anderes Zeichen: Sitzung beenden, das Zeichen schreibt die IDE.</summary>
    Finish);

  TAtlasLinkedKeys = record
  public const
    cKeyBack = $08;
    cKeyReturn = $0D;
    cKeyShift = $10;
    cKeyControl = $11;
    cKeyMenu = $12;
    cKeyEscape = $1B;
    cKeyDelete = $2E;
  public
    /// <summary>Taste AKey; AModified: Strg, Alt oder Umschalt gedrückt. AActive: Sitzung läuft, AProblem: der
    /// neue Name stößt mit etwas zusammen.</summary>
    class function KeyStep(AKey: Word; AModified, AActive, AProblem: Boolean): TAtlasLinkedKeyStep; static;
    /// <summary>Zeichen ATyped; AHighPending: ein hohes Surrogat wartet.</summary>
    class function CharStep(ATyped: Char; AHighPending: Boolean): TAtlasLinkedCharStep; static;
  end;

implementation

uses
  Atlas.Text.Chars;

{ TAtlasLinkedKeys }

class function TAtlasLinkedKeys.KeyStep(AKey: Word; AModified, AActive, AProblem: Boolean): TAtlasLinkedKeyStep;
begin
  Result := TAtlasLinkedKeyStep.Pass;
  if AModified or (AKey = cKeyShift) or (AKey = cKeyControl) or (AKey = cKeyMenu) then
  begin
    Exit;
  end;
  case AKey of
    cKeyEscape:
      if AActive and AProblem then
      begin
        Result := TAtlasLinkedKeyStep.RestoreAndFinish;
      end
      else if AActive then
      begin
        Result := TAtlasLinkedKeyStep.Finish;
      end;
    cKeyReturn:
      if AActive then
      begin
        Result := TAtlasLinkedKeyStep.Finish;
      end;
    cKeyBack:
      Result := TAtlasLinkedKeyStep.Backspace;
    cKeyDelete:
      Result := TAtlasLinkedKeyStep.Delete;
  end;
end;

class function TAtlasLinkedKeys.CharStep(ATyped: Char; AHighPending: Boolean): TAtlasLinkedCharStep;
begin
  if (ATyped < ' ') or (ATyped = #127) then
  begin
    Result := TAtlasLinkedCharStep.Ignore;
  end
  else if (ATyped >= #$D800) and (ATyped <= #$DBFF) then
  begin
    Result := TAtlasLinkedCharStep.HighSurrogate;
  end
  else if AHighPending and (ATyped >= #$DC00) and (ATyped <= #$DFFF) then
  begin
    Result := TAtlasLinkedCharStep.LowSurrogate;
  end
  else if TTextChars.IsIdentChar(ATyped) then
  begin
    Result := TAtlasLinkedCharStep.Insert;
  end
  else
  begin
    Result := TAtlasLinkedCharStep.Finish;
  end;
end;

end.
