unit Atlas.Core.Style.Signal;

// Signalfarben je Design (#1255): Zustandspunkte (Statusfeld, Atlas-Statusleiste,
// Statusfenster, Einrichtung), Plaketten und Befundsymbole. Früher nahmen sie
// die Textfarben Add/Warn/Error/Muted, die für Text auf der Fensterfläche
// gedacht sind; im hellen Design waren sie dunkel und entsättigt und als
// kleiner Punkt kaum zu unterscheiden, das gelbe Warndreieck hatte auf hellem
// Grund nur 1,8 : 1. Jetzt (Variante A, Entwurf in #1255):
// - Hell: kräftige Füllung (Fill) mit dunklem Rand (Ring); der Rand hält
//   mindestens 4 : 1 zur Leistenfläche, die Füllung macht die Farbe auf einen
//   Blick erkennbar.
// - Dunkel: helle, gesättigte Füllung ohne eigenen Rand (Ring = Fill), auf den
//   dunklen Flächen der IDE mindestens 4 : 1.
// - Mark: Zeichen auf der Füllung (Kreuz, „i“, Ausrufezeichen); Solid und
//   OnSolid: Plakette mit Zahl darauf.
// Die Farben gehören zur Palette der Fläche, auf der sie liegen
// (TAtlasColors.Signals; für Leisten ForChrome mit der Fläche der Leiste).

interface

uses
  Atlas.Core.Style.Color,
  Atlas.Core.Status.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Bedeutung einer Signalfarbe: in Ordnung, Warnung bzw. läuft, Fehler, ohne Aussage, Hinweis.</summary>
  TAtlasSignalKind = (Ok, Warn, Error, Idle, Info);
{$SCOPEDENUMS OFF}

  TAtlasSignal = record
    /// <summary>Fläche von Punkt und Symbol.</summary>
    Fill: TAtlasColor;
    /// <summary>Rand von Punkt und Symbol; trägt den Kontrast zur Fläche darunter.</summary>
    Ring: TAtlasColor;
    /// <summary>Zeichen auf Fill (Kreuz, „i“, Ausrufezeichen).</summary>
    Mark: TAtlasColor;
    /// <summary>Fläche einer Plakette mit Text.</summary>
    Solid: TAtlasColor;
    /// <summary>Text auf Solid.</summary>
    OnSolid: TAtlasColor;
  end;

  TAtlasSignals = record
    Items: array[TAtlasSignalKind] of TAtlasSignal;
    function Get(AKind: TAtlasSignalKind): TAtlasSignal;
    /// <summary>Signal zum Zustand einer Statuszeile.</summary>
    function ForStatus(AState: TAtlasStatusState): TAtlasSignal;
    class function Light: TAtlasSignals; static;
    class function Dark: TAtlasSignals; static;
    class function KindOf(AState: TAtlasStatusState): TAtlasSignalKind; static;
  end;

implementation

function Signal(const AFill, ARing, AMark, ASolid, AOnSolid: string): TAtlasSignal;
begin
  Result.Fill := TAtlasColorMath.FromHex(AFill);
  Result.Ring := TAtlasColorMath.FromHex(ARing);
  Result.Mark := TAtlasColorMath.FromHex(AMark);
  Result.Solid := TAtlasColorMath.FromHex(ASolid);
  Result.OnSolid := TAtlasColorMath.FromHex(AOnSolid);
end;

{ TAtlasSignals }

class function TAtlasSignals.Light: TAtlasSignals;
begin
  Result.Items[TAtlasSignalKind.Ok] := Signal('#22C55E', '#15803D', '#FFFFFF', '#15803D', '#FFFFFF');
  // Ausrufezeichen dunkel: Weiß hätte auf dem Bernstein nur 2,1 : 1.
  Result.Items[TAtlasSignalKind.Warn] := Signal('#F59E0B', '#B45309', '#3A2500', '#B45309', '#FFFFFF');
  Result.Items[TAtlasSignalKind.Error] := Signal('#EF4444', '#B91C1C', '#FFFFFF', '#B91C1C', '#FFFFFF');
  Result.Items[TAtlasSignalKind.Idle] := Signal('#A3ADBD', '#64748B', '#FFFFFF', '#64748B', '#FFFFFF');
  Result.Items[TAtlasSignalKind.Info] := Signal('#3B82F6', '#1D4ED8', '#FFFFFF', '#1D4ED8', '#FFFFFF');
end;

class function TAtlasSignals.Dark: TAtlasSignals;
begin
  // Helle Füllung: Zeichen und Text darauf dunkel.
  Result.Items[TAtlasSignalKind.Ok] := Signal('#4ADE80', '#4ADE80', '#15181D', '#4ADE80', '#15181D');
  Result.Items[TAtlasSignalKind.Warn] := Signal('#FBBF24', '#FBBF24', '#15181D', '#FBBF24', '#15181D');
  Result.Items[TAtlasSignalKind.Error] := Signal('#F87171', '#F87171', '#15181D', '#F87171', '#15181D');
  Result.Items[TAtlasSignalKind.Idle] := Signal('#9AA3B2', '#9AA3B2', '#15181D', '#9AA3B2', '#15181D');
  Result.Items[TAtlasSignalKind.Info] := Signal('#60A5FA', '#60A5FA', '#15181D', '#60A5FA', '#15181D');
end;

class function TAtlasSignals.KindOf(AState: TAtlasStatusState): TAtlasSignalKind;
begin
  case AState of
    TAtlasStatusState.Green:
      Result := TAtlasSignalKind.Ok;
    TAtlasStatusState.Yellow:
      Result := TAtlasSignalKind.Warn;
    TAtlasStatusState.Red:
      Result := TAtlasSignalKind.Error;
  else
    Result := TAtlasSignalKind.Idle;
  end;
end;

function TAtlasSignals.Get(AKind: TAtlasSignalKind): TAtlasSignal;
begin
  Result := Items[AKind];
end;

function TAtlasSignals.ForStatus(AState: TAtlasStatusState): TAtlasSignal;
begin
  Result := Items[KindOf(AState)];
end;

end.
