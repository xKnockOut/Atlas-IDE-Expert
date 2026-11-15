unit Atlas.Core.Editor.ExitPointAsk;

// Wann Atlas den Server nach Austrittspunkten fragt (#698), ohne Open Tools API: je Wort eine Anfrage, erst wenn
// der Cursor einige Takte auf demselben Wort ruht. Cursorbewegungen innerhalb des Worts ändern den Schlüssel
// nicht; eine neue Fassung des Texts oder andere Schalter schon. Dazu die Argumente von atlas.server.exitPoints.

interface

type
  TAtlasExitPointAsk = record
  private
    FIdleKey: string;
    FAskedKey: string;
    FIdleCount: Integer;
  public
    /// <summary>Kein Wort mehr unter dem Cursor: alles vergessen.</summary>
    procedure Reset;
    /// <summary>Antwort verworfen: Dasselbe Wort darf wieder fragen.</summary>
    procedure ForgetAsked;
    /// <summary>Ein Takt auf dem Wort mit AKey: True genau einmal, wenn der Cursor ATicks Takte darauf ruhte.
    /// </summary>
    function Due(const AKey: string; ATicks: Integer): Boolean;
    /// <summary>Schlüssel je Wort: Datei, Fassung, Zeile und Anfang des Worts, Schalter.</summary>
    class function KeyOf(const AFileName: string; AVersion: Cardinal; ALine, AWordStart: Integer; AExceptions,
      ALoops: Boolean): string; static;
    /// <summary>Argumente als JSON-Text: URI, Position (0-basiert), Schalter.</summary>
    class function Arguments(const AUri: string; ALine, ACharacter: Integer; AExceptions, ALoops: Boolean): string;
      static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  System.JSON;

{ TAtlasExitPointAsk }

procedure TAtlasExitPointAsk.Reset;
begin
  FIdleKey := '';
  FAskedKey := '';
  FIdleCount := 0;
end;

procedure TAtlasExitPointAsk.ForgetAsked;
begin
  FAskedKey := '';
end;

function TAtlasExitPointAsk.Due(const AKey: string; ATicks: Integer): Boolean;
begin
  Result := False;
  if AKey <> FIdleKey then
  begin
    FIdleKey := AKey;
    FIdleCount := 0;
    Exit;
  end;
  Inc(FIdleCount);
  Result := (FIdleCount >= ATicks) and (AKey <> FAskedKey);
  if Result then
  begin
    FAskedKey := AKey;
  end;
end;

class function TAtlasExitPointAsk.KeyOf(const AFileName: string; AVersion: Cardinal; ALine, AWordStart: Integer;
  AExceptions, ALoops: Boolean): string;
begin
  Result := Format('%s|%d|%d|%d|%d|%d', [AFileName, AVersion, ALine, AWordStart, Ord(AExceptions), Ord(ALoops)]);
end;

class function TAtlasExitPointAsk.Arguments(const AUri: string; ALine, ACharacter: Integer; AExceptions,
  ALoops: Boolean): string;
var
  mValues: TJSONArray;
  mPosition, mOptions: TJSONObject;
begin
  mValues := TJSONArray.Create;
  try
    mValues.Add(AUri);
    mPosition := TJSONObject.Create;
    mPosition.AddPair('line', TJSONNumber.Create(ALine));
    mPosition.AddPair('character', TJSONNumber.Create(ACharacter));
    mValues.AddElement(mPosition);
    mOptions := TJSONObject.Create;
    mOptions.AddPair('exceptions', TJSONBool.Create(AExceptions));
    mOptions.AddPair('loops', TJSONBool.Create(ALoops));
    mValues.AddElement(mOptions);
    Result := mValues.ToJSON;
  finally
    mValues.Free;
  end;
end;

end.
