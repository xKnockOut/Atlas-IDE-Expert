unit Atlas.Core.Commands.KeyFallback;

// Rückfall einer Atlas-Taste an die IDE. Tasten mit Rückfall (AddAttemptKey,
// etwa F9 und Strg+F2 der Startverbünde) geben einen Tastendruck, mit dem
// Atlas nichts anfängt, an die nächste Bindung weiter (krNextProc). Das
// erreicht nur Tastaturbindungen der IDE (Klassennavigation, „Erneut
// suchen“), nicht die Aktionen des Hauptmenüs: Ohne weitere Bindung ging die
// Taste verloren, F9 setzte das angehaltene Programm nicht mehr fort und
// Strg+F2 beendete es nicht. Deshalb sucht die Bindung zuerst eine Aktion
// der IDE mit dieser Taste und führt die erste freigegebene aus; nur ohne
// solche Aktion bleibt es bei krNextProc. Eigene Aktionen von Atlas
// (Kategorie „Atlas“) zählen nicht, sonst liefe derselbe Befehl im Kreis.
// Hier nur die Auswahl, ohne VCL und Open Tools API.

interface

type
  /// <summary>Aktion der IDE, wie die Bindung sie für den Rückfall sieht.</summary>
  TAtlasFallbackAction = record
    Category: string;
    /// <summary>Kürzel der Aktion samt weiterer Kürzel; 0 = ohne.</summary>
    ShortCuts: TArray<Integer>;
  end;

  TAtlasKeyFallback = class
  public
    /// <summary>Indizes der Aktionen aus AActions, die AKey belegen und nicht von Atlas sind, in ihrer
    /// Reihenfolge; die Bindung führt die erste freigegebene davon aus. Leer bei AKey 0.</summary>
    class function Candidates(const AActions: TArray<TAtlasFallbackAction>; AKey: Integer): TArray<Integer>;
      static;
  end;

implementation

uses
  Atlas.Core.Commands.KeyScan;

function HasKey(const AAction: TAtlasFallbackAction; AKey: Integer): Boolean;
var
  mKey: Integer;
begin
  Result := False;
  for mKey in AAction.ShortCuts do
  begin
    if mKey = AKey then
    begin
      Exit(True);
    end;
  end;
end;

{ TAtlasKeyFallback }

class function TAtlasKeyFallback.Candidates(const AActions: TArray<TAtlasFallbackAction>;
  AKey: Integer): TArray<Integer>;
var
  mIndex, mCount: Integer;
begin
  Result := nil;
  if AKey = 0 then
  begin
    Exit;
  end;
  SetLength(Result, Length(AActions));
  mCount := 0;
  for mIndex := 0 to High(AActions) do
  begin
    if HasKey(AActions[mIndex], AKey) and not TAtlasKeyScan.IsAtlasCategory(AActions[mIndex].Category) then
    begin
      Result[mCount] := mIndex;
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

end.
