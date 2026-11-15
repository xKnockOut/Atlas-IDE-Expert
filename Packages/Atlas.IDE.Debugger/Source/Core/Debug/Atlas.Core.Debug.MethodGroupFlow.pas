unit Atlas.Core.Debug.MethodGroupFlow;

// Entscheidungen der Methodenhaltepunkte (#855) außerhalb von Suche und Speicher, ohne IDE prüfbar (#1967): mit
// welcher Gruppe der Dialog beginnt, welche schon gesehenen Treffer eine Gruppe behält, ob „Umschalten“ ein- oder
// ausschaltet und wie die neuen Treffer in der Meldung heißen. Atlas.IDE.Debug.MethodBreakpoints fragt Debugger,
// Editor und Server.

interface

uses
  Atlas.Core.Debug.MethodBreakpoints;

type
  TAtlasMethodGroupFlow = class
  public const
    /// <summary>So viele Namen nennt die Meldung über neue Treffer, dann „…“.</summary>
    cShownNames = 5;
  public
    /// <summary>Gruppe beim Öffnen des Dialogs: die letzte, außer an der Schreibmarke steht ein anderes Muster
    /// (dann neu mit Überschreibungen und Überladungen). Known ist leer.</summary>
    class function StartGroup(const ALast: TAtlasMethodGroup; const AStart: string): TAtlasMethodGroup; static;
    /// <summary>Schon gesehene Treffer AKnown der gespeicherten Gruppe dazunehmen (ohne Doppelte).</summary>
    class procedure MergeKnown(var AGroup: TAtlasMethodGroup; const AKnown: TArray<string>); static;
    /// <summary>Neuer Zustand beim Umschalten: alle ein, außer alle sind schon ein.</summary>
    class function ToggleTo(const AEnabled: TArray<Boolean>): Boolean; static;
    /// <summary>„TKunde.A, TKunde.B, …“: höchstens cShownNames Namen.</summary>
    class function HitNames(const AHits: TAtlasMethodHits): string; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasMethodGroupFlow }

class function TAtlasMethodGroupFlow.StartGroup(const ALast: TAtlasMethodGroup;
  const AStart: string): TAtlasMethodGroup;
begin
  Result := ALast;
  if (Result.Pattern = '') or (AStart <> '') and not SameText(AStart, ALast.Pattern) then
  begin
    Result := Default(TAtlasMethodGroup);
    Result.Pattern := AStart;
    Result.Overrides := True;
    Result.Overloads := True;
  end;
  Result.Known := nil;
end;

class procedure TAtlasMethodGroupFlow.MergeKnown(var AGroup: TAtlasMethodGroup; const AKnown: TArray<string>);
var
  mKey: string;
begin
  for mKey in AKnown do
  begin
    if not AGroup.Knows(mKey) then
    begin
      AGroup.Known := AGroup.Known + [mKey];
    end;
  end;
end;

class function TAtlasMethodGroupFlow.ToggleTo(const AEnabled: TArray<Boolean>): Boolean;
var
  mEnabled: Boolean;
begin
  Result := False;
  for mEnabled in AEnabled do
  begin
    if not mEnabled then
    begin
      Exit(True);
    end;
  end;
end;

class function TAtlasMethodGroupFlow.HitNames(const AHits: TAtlasMethodHits): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(AHits) do
  begin
    if mIndex = cShownNames then
    begin
      Result := Result + ', …';
      Break;
    end;
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + AHits[mIndex].DisplayName;
  end;
end;

end.
