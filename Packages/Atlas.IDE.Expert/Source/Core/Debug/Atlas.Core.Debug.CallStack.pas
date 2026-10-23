unit Atlas.Core.Debug.CallStack;

// Aufrufstapel eines angehaltenen Threads (#517), ohne VCL und Open Tools API.
// Die IDE-Schicht liest ihn über IOTAThread (GetCallHeader, GetCallPos);
// hier liegen die Rahmen und was Atlas aus ihnen ableitet:
//   - FirstWithSource: der oberste Rahmen mit Datei und Zeile (Ort einer
//     Exception im Verlauf).
//   - Routine: Name der Routine aus der Kopfzeile der IDE
//     („Unit1.TForm1.Button1Click(Self=$02A3F2C0)“ → „Unit1.TForm1.Button1Click“).

interface

type
  TAtlasDebugFrame = record
    /// <summary>Kopfzeile wie im Fenster Aufrufstack der IDE.</summary>
    Header: string;
    /// <summary>Datei ('' = ohne Quelltext).</summary>
    FileName: string;
    /// <summary>Zeile, 1-basiert; 0 = unbekannt.</summary>
    Line: Integer;
    class function Create(const AHeader, AFileName: string; ALine: Integer): TAtlasDebugFrame; static;
    function HasSource: Boolean;
    /// <summary>Routine ohne Parameterliste und Adresse.</summary>
    function Routine: string;
  end;

  TAtlasDebugFrames = TArray<TAtlasDebugFrame>;

  TAtlasDebugCallStack = record
  public const
    /// <summary>Höchstens so viele Rahmen liest die IDE-Schicht.</summary>
    MaxFrames = 64;
  public
    /// <summary>Index des obersten Rahmens mit Quelltext; -1 ohne.</summary>
    class function FirstWithSource(const AFrames: TAtlasDebugFrames): Integer; static;
    /// <summary>Routine aus einer Kopfzeile der IDE (siehe Kopf).</summary>
    class function RoutineOf(const AHeader: string): string; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasDebugFrame }

class function TAtlasDebugFrame.Create(const AHeader, AFileName: string; ALine: Integer): TAtlasDebugFrame;
begin
  Result.Header := AHeader;
  Result.FileName := AFileName;
  Result.Line := ALine;
end;

function TAtlasDebugFrame.HasSource: Boolean;
begin
  Result := (FileName <> '') and (Line > 0);
end;

function TAtlasDebugFrame.Routine: string;
begin
  Result := TAtlasDebugCallStack.RoutineOf(Header);
end;

{ TAtlasDebugCallStack }

class function TAtlasDebugCallStack.FirstWithSource(const AFrames: TAtlasDebugFrames): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(AFrames) do
    if AFrames[Index].HasSource then
      Exit(Index);
  Result := -1;
end;

class function TAtlasDebugCallStack.RoutineOf(const AHeader: string): string;
var
  Stop: Integer;
begin
  Result := Trim(AHeader);
  // Rahmen ohne Symbole zeigen nur die Adresse („:7714C3E2 KERNELBASE.RaiseException + 0x62“).
  if (Result <> '') and (Result[1] = ':') then
  begin
    Stop := Pos(' ', Result);
    if Stop > 0 then
      Result := Trim(Copy(Result, Stop + 1, MaxInt));
  end;
  Stop := Pos('(', Result);
  if Stop > 0 then
    Result := Trim(Copy(Result, 1, Stop - 1));
  Stop := Pos(' + ', Result);
  if Stop > 0 then
    Result := Trim(Copy(Result, 1, Stop - 1));
end;

end.
