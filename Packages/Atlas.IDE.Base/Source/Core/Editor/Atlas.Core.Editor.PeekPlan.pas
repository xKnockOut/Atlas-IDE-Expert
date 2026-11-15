unit Atlas.Core.Editor.PeekPlan;

// Definition und Referenzen einblenden (#505), Entscheidungen des Fensters ohne
// IDE und VCL (#1967):
// - Tasten ohne Umschalter: Escape schließt, Enter öffnet die Stelle, Pfeile
//   wechseln das Ziel (bei nur einem scrollen sie), Bild auf/ab scrollt.
// - Platz: unter der Cursorzeile, so breit wie der Editor; passt es nicht
//   darunter und ist oben mehr Platz, darüber; nie größer als der Arbeitsbereich.

interface

uses
  System.Classes,
  System.Types;

type
  TAtlasPeekKey = (None, Close, Open, Previous, Next, ScrollUp, ScrollDown, PageUp, PageDown);

  TAtlasPeekPlan = record
  public const
    // Virtuelle Tastencodes wie in Windows (VK_…); System.UITypes von FPC kennt sie nicht.
    cKeyReturn = 13;
    cKeyEscape = 27;
    cKeyPrior = 33;
    cKeyNext = 34;
    cKeyUp = 38;
    cKeyDown = 40;
  public
    /// <summary>Wirkung der Taste AKey (virtueller Code) bei ACount Zielen; None für fremde Tasten.</summary>
    class function KeyOf(AKey: Word; AShift: TShiftState; ACount: Integer): TAtlasPeekKey; static;
    /// <summary>Bleibt das Fenster nach der Taste offen (Ansicht neu zeichnen)?</summary>
    class function Stays(AKey: TAtlasPeekKey): Boolean; static;
    /// <summary>Fenster AHeight hoch zur Cursorzeile ACaret im Editor AEditor, begrenzt auf AArea.</summary>
    class function Bounds(const ACaret, AEditor, AArea: TRect; AHeight: Integer): TRect; static;
  end;

implementation

uses
  System.Math;

class function TAtlasPeekPlan.KeyOf(AKey: Word; AShift: TShiftState; ACount: Integer): TAtlasPeekKey;
begin
  Result := TAtlasPeekKey.None;
  if AShift <> [] then
  begin
    Exit;
  end;
  case AKey of
    cKeyEscape:
      Result := TAtlasPeekKey.Close;
    cKeyReturn:
      Result := TAtlasPeekKey.Open;
    cKeyUp:
      if ACount > 1 then
      begin
        Result := TAtlasPeekKey.Previous;
      end
      else
      begin
        Result := TAtlasPeekKey.ScrollUp;
      end;
    cKeyDown:
      if ACount > 1 then
      begin
        Result := TAtlasPeekKey.Next;
      end
      else
      begin
        Result := TAtlasPeekKey.ScrollDown;
      end;
    cKeyPrior:
      Result := TAtlasPeekKey.PageUp;
    cKeyNext:
      Result := TAtlasPeekKey.PageDown;
  end;
end;

class function TAtlasPeekPlan.Stays(AKey: TAtlasPeekKey): Boolean;
begin
  Result := not (AKey in [TAtlasPeekKey.None, TAtlasPeekKey.Close, TAtlasPeekKey.Open]);
end;

class function TAtlasPeekPlan.Bounds(const ACaret, AEditor, AArea: TRect; AHeight: Integer): TRect;
begin
  if (ACaret.Bottom + AHeight <= AArea.Bottom) or (ACaret.Top - AArea.Top < AArea.Bottom - ACaret.Bottom) then
  begin
    Result := TRect.Create(AEditor.Left, ACaret.Bottom + 1, AEditor.Right, Min(AArea.Bottom,
      ACaret.Bottom + 1 + AHeight));
  end
  else
  begin
    Result := TRect.Create(AEditor.Left, Max(AArea.Top, ACaret.Top - 1 - AHeight), AEditor.Right, ACaret.Top - 1);
  end;
  Result.Left := Max(Result.Left, AArea.Left);
  Result.Right := Min(Result.Right, AArea.Right);
end;

end.
