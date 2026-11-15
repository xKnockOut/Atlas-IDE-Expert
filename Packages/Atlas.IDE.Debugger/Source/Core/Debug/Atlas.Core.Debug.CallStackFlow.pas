unit Atlas.Core.Debug.CallStackFlow;

// Entscheidungen des Fensters „Atlas-Aufrufstapel“ (#843) außerhalb von Inhalt und Parametern, ohne IDE prüfbar
// (#1967): Nachfragen beim verzögerten Stapel, ob eine Antwort des Servers noch zählt, welcher Parameter als
// nächster ausgewertet wird, wann das Namensfeld eines Objekts gefragt wird und welcher Rahmen sich öffnen lässt.
// Atlas.IDE.Debug.CallStack fragt Debugger, Server und Fenster.

interface

uses
  Atlas.Core.Debug.OwnCode,
  Atlas.Core.Debug.CallStackView;

type
  TAtlasCallStackFlow = class
  public
    /// <summary>Stapel noch nicht da: ARetries hochzählen; True, solange höchstens AMax Versuche.</summary>
    class function Retry(var ARetries: Integer; AMax: Integer): Boolean; static;
    /// <summary>Zählt die Antwort ARequest für Rahmen AFrame noch: jüngste Anfrage (ACurrent), es wird auf sie
    /// gewartet (AWaiting) und der Rahmen besteht in AStack?</summary>
    class function Accepts(ARequest, ACurrent: Integer; AWaiting: Boolean; AFrame: Integer;
      const AStack: TAtlasDebugStackView): Boolean; static;
    /// <summary>Nächster auszuwertender Parameter in den sichtbaren Rahmen ARows: Rahmen AFrame, Parameter AParam.
    /// </summary>
    class function NextParam(const AStack: TAtlasDebugStackView; const ARows: TAtlasDebugStackRows; out AFrame,
      AParam: Integer): Boolean; static;
    /// <summary>Objekt: Namensfeld fragen, wenn der Wert eine Adresse ist (ARaw) oder im obersten Rahmen.</summary>
    class function AsksName(const ARaw: string; AFrame: Integer): Boolean; static;
    /// <summary>Namensfeld nur, wenn die Auswertung gelang (AOk) und es ein String ist.</summary>
    class function NameOf(AOk: Boolean; const AName: string): string; static;
    /// <summary>Lässt sich Rahmen AIndex öffnen (vorhanden, mit Quelltext)?</summary>
    class function CanOpen(const AStack: TAtlasDebugStackView; AIndex: Integer): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.CallStackParams;

{ TAtlasCallStackFlow }

class function TAtlasCallStackFlow.Retry(var ARetries: Integer; AMax: Integer): Boolean;
begin
  Inc(ARetries);
  Result := ARetries <= AMax;
end;

class function TAtlasCallStackFlow.Accepts(ARequest, ACurrent: Integer; AWaiting: Boolean; AFrame: Integer;
  const AStack: TAtlasDebugStackView): Boolean;
begin
  // Nur die jüngste Antwort, und nur, solange auf sie gewartet wird.
  Result := (ARequest = ACurrent) and AWaiting and (AFrame <= High(AStack.Entries));
end;

class function TAtlasCallStackFlow.NextParam(const AStack: TAtlasDebugStackView; const ARows: TAtlasDebugStackRows;
  out AFrame, AParam: Integer): Boolean;
var
  mRow: TAtlasDebugStackRow;
  mParam: Integer;
begin
  AFrame := -1;
  AParam := -1;
  for mRow in ARows do
  begin
    if mRow.Kind <> TAtlasDebugStackRowKind.Frame then
    begin
      Continue;
    end;
    for mParam := 0 to High(AStack.Entries[mRow.First].Params) do
    begin
      if TAtlasCallStackParams.ExpressionFor(AStack.Entries[mRow.First].Params[mParam], mRow.First = 0) <> '' then
      begin
        AFrame := mRow.First;
        AParam := mParam;
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

class function TAtlasCallStackFlow.AsksName(const ARaw: string; AFrame: Integer): Boolean;
begin
  Result := TAtlasCallStackParams.IsAddress(ARaw) or (AFrame = 0);
end;

class function TAtlasCallStackFlow.NameOf(AOk: Boolean; const AName: string): string;
begin
  Result := '';
  if AOk and AName.StartsWith('''') then
  begin
    Result := AName;
  end;
end;

class function TAtlasCallStackFlow.CanOpen(const AStack: TAtlasDebugStackView; AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(AStack.Entries)) and AStack.Entries[AIndex].Frame.HasSource;
end;

end.
