unit Atlas.Core.Commands.QuickOpenTarget;

// Ziel eines Eintrags von „Datei und Symbol schnell öffnen“ (#503, #1967), ohne VCL und Open Tools API. Der
// Eintrag trägt sein Ziel selbst: Datei in Description, „Zeile:Zeichen“ (0-basiert, Zeile -1 = nur öffnen) in Id.
// So braucht das Ausführen keinen Zustand des Fensters, das sich dabei schon freigibt.

interface

type
  TAtlasQuickOpenTarget = record
    FileName: string;
    /// <summary>0-basiert; -1 = Datei nur öffnen.</summary>
    Line: Integer;
    /// <summary>0-basiert.</summary>
    Character: Integer;
    /// <summary>Kennung des Eintrags für Zeile und Zeichen.</summary>
    class function IdOf(ALine, ACharacter: Integer): string; static;
    /// <summary>Ziel aus Kennung und Datei eines Eintrags; False ohne Datei oder ohne „Zeile:Zeichen“ (Hinweise).
    /// Unlesbare Zeile heißt nur öffnen, unlesbares Zeichen 0.</summary>
    class function TryParse(const AId, AFileName: string; out ATarget: TAtlasQuickOpenTarget): Boolean; static;
    /// <summary>Zeile für Dateitreffer aus der Eingabe „Datei:123“ (1-basiert, 0 = ohne): 0-basiert, -1 ohne.
    /// </summary>
    class function FileLine(AQueryLine: Integer): Integer; static;
    /// <summary>Zweite Zeile eines Projektsymbols: Container und Datei (ohne Pfad), ohne Container nur die Datei.
    /// </summary>
    class function SymbolPlace(const AContainer, AFileName: string): string; static;
    /// <summary>Springt an eine Zeile; sonst nur die Datei öffnen.</summary>
    function GoesToLine: Boolean;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasQuickOpenTarget }

class function TAtlasQuickOpenTarget.IdOf(ALine, ACharacter: Integer): string;
begin
  Result := Format('%d:%d', [ALine, ACharacter]);
end;

class function TAtlasQuickOpenTarget.TryParse(const AId, AFileName: string;
  out ATarget: TAtlasQuickOpenTarget): Boolean;
var
  mParts: TArray<string>;
begin
  ATarget := Default(TAtlasQuickOpenTarget);
  mParts := AId.Split([':']);
  Result := (AFileName <> '') and (Length(mParts) = 2);
  if not Result then
  begin
    Exit;
  end;
  ATarget.FileName := AFileName;
  ATarget.Line := StrToIntDef(mParts[0], -1);
  ATarget.Character := StrToIntDef(mParts[1], 0);
end;

class function TAtlasQuickOpenTarget.FileLine(AQueryLine: Integer): Integer;
begin
  Result := -1;
  if AQueryLine > 0 then
  begin
    Result := AQueryLine - 1;
  end;
end;

class function TAtlasQuickOpenTarget.SymbolPlace(const AContainer, AFileName: string): string;
begin
  Result := ExtractFileName(AFileName);
  if AContainer <> '' then
  begin
    Result := AContainer + ' · ' + Result;
  end;
end;

function TAtlasQuickOpenTarget.GoesToLine: Boolean;
begin
  Result := Line >= 0;
end;

end.
