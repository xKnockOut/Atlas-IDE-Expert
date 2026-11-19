unit Atlas.Core.Designer.FormStore;

// Ablage von Formulardaten der Designer-Werkzeuge (Auswahlsätze, Gruppen),
// ohne VCL und Windows: geteilt liegt die Datei neben dem Formular und der
// Schlüssel ist nur der Dateiname (die Datei wandert mit dem Projekt);
// lokal liegt sie unter <LOCALAPPDATA>\Atlas (ohne LOCALAPPDATA im
// Temp-Ordner) und der Schlüssel ist der volle Pfad des Formulars.

interface

type
  TAtlasDesignerFormStore = class
  public
    /// <summary>Schlüssel des Formulars AFormFile in der Datei: geteilt nur der Dateiname, sonst der Pfad.</summary>
    class function FormKey(const AFormFile: string; AShared: Boolean): string; static;
    /// <summary>Datei der Ablage: geteilt ASharedName neben AFormFile, sonst ALocalName unter ALocalData\Atlas
    /// (ATemp, wenn ALocalData leer ist).</summary>
    class function StorePath(const AFormFile: string; AShared: Boolean; const ALocalData, ATemp, ASharedName,
      ALocalName: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils;

const
  /// <summary>Ordner der lokalen Ablage unter LOCALAPPDATA bzw. Temp.</summary>
  cLocalFolder = 'Atlas';

{ TAtlasDesignerFormStore }

class function TAtlasDesignerFormStore.FormKey(const AFormFile: string; AShared: Boolean): string;
begin
  Result := AFormFile;
  if AShared then
  begin
    Result := ExtractFileName(AFormFile);
  end;
end;

class function TAtlasDesignerFormStore.StorePath(const AFormFile: string; AShared: Boolean; const ALocalData, ATemp,
  ASharedName, ALocalName: string): string;
var
  mLocal: string;
begin
  if AShared then
  begin
    Exit(TPath.Combine(ExtractFilePath(AFormFile), ASharedName));
  end;
  mLocal := ALocalData;
  if mLocal = '' then
  begin
    mLocal := ATemp;
  end;
  Result := TPath.Combine(TPath.Combine(mLocal, cLocalFolder), ALocalName);
end;

end.
