unit Atlas.Core.Commands.KeyStroke;

// Ein Tastendruck löst einen Befehl von Atlas genau einmal aus. Das
// Kontextmenü des Editors zeigt die Tastenkürzel als ShortCut seiner Aktionen
// (nur so stehen sie im Menü der IDE rechtsbündig); dieselbe Taste belegt aber
// auch die Tastaturbindung von Atlas. Je nach Weg der Taste durch die IDE
// erreicht sie beide. Wer den Tastendruck zuerst beansprucht (Claim), führt
// den Befehl aus; der zweite Empfänger desselben Tastendrucks lässt ihn aus.
// Einen Tastendruck kennzeichnen Taste und Zeit der Nachricht (unter Windows
// GetMessageTime): Beide Empfänger laufen in derselben Nachricht, die
// Wiederholung einer gehaltenen Taste hat eine neue Zeit. Ein Mausklick ins
// Menü hat die Zeit seiner eigenen Nachricht und läuft deshalb immer.
// Ohne VCL und Open Tools API; nur im Hauptthread aufrufen.

interface

type
  TAtlasKeyStroke = class
  private class var
    FKey: Integer;
    FTime: Cardinal;
    FClaimed: Boolean;
  public
    /// <summary>True, wenn der Tastendruck AKey zur Nachrichtenzeit ATime noch nicht beansprucht war (der Aufrufer
    /// führt den Befehl aus); False beim zweiten Empfänger desselben Tastendrucks. AKey 0 (ohne Kürzel) ist immer
    /// frei.</summary>
    class function Claim(AKey: Integer; ATime: Cardinal): Boolean; static;
    /// <summary>Vergisst den letzten Tastendruck (Tests).</summary>
    class procedure Reset; static;
  end;

implementation

class function TAtlasKeyStroke.Claim(AKey: Integer; ATime: Cardinal): Boolean;
begin
  Result := True;
  if AKey = 0 then
  begin
    Exit;
  end;
  if FClaimed and (FKey = AKey) and (FTime = ATime) then
  begin
    Exit(False);
  end;
  FKey := AKey;
  FTime := ATime;
  FClaimed := True;
end;

class procedure TAtlasKeyStroke.Reset;
begin
  FKey := 0;
  FTime := 0;
  FClaimed := False;
end;

end.
