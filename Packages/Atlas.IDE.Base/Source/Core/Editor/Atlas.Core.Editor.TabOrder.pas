unit Atlas.Core.Editor.TabOrder;

// Reihenfolge der Reiter im Editorfenster: Die IDE nennt nur die Beschriftungen (Dateiname ohne Pfad, mit oder
// ohne Endung, ggf. mit Markierung wie „*“). Daraus ordnet TAtlasEditorTabOrder die Dateien der offenen Puffer;
// genutzt von „Fortsetzen“ der Willkommensseite und vom IDE-Zustand für KI-Assistenten (#2050).

interface

type
  TAtlasEditorTabOrder = class
  public
    /// <summary>Beschriftung eines Reiters ohne Markierungen (z. B. „*“ für geändert) und Leerraum.</summary>
    class function CaptionName(const ACaption: string): string; static;
    /// <summary>Dateien in der Reihenfolge der Reiterbeschriftungen ACaptions; nicht zuordenbare bleiben in ihrer
    /// Reihenfolge dahinter.</summary>
    class function Order(const AFiles, ACaptions: TArray<string>): TArray<string>; static;
  end;

implementation

uses
  System.SysUtils;

/// <summary>Passt die Datei AFile zur Beschriftung AName (mit oder ohne Endung)?</summary>
function Matches(const AFile, AName: string): Boolean;
var
  mName: string;
begin
  // Pfade mit „\“ auch dort, wo die Tests nicht unter Windows laufen.
  mName := ExtractFileName(AFile.Replace('\', PathDelim).Replace('/', PathDelim));
  Result := SameText(mName, AName) or SameText(ChangeFileExt(mName, ''), AName);
end;

class function TAtlasEditorTabOrder.CaptionName(const ACaption: string): string;
begin
  Result := Trim(ACaption);
  while (Result <> '') and CharInSet(Result[Length(Result)], ['*', ' ']) do
  begin
    Delete(Result, Length(Result), 1);
  end;
  while (Result <> '') and CharInSet(Result[1], ['*', ' ', '&']) do
  begin
    Delete(Result, 1, 1);
  end;
end;

class function TAtlasEditorTabOrder.Order(const AFiles, ACaptions: TArray<string>): TArray<string>;
var
  mUsed: TArray<Boolean>;
  mCaption, mName: string;
  mIndex: Integer;
begin
  Result := nil;
  SetLength(mUsed, Length(AFiles));
  for mCaption in ACaptions do
  begin
    mName := CaptionName(mCaption);
    // Gleich benannte Dateien in verschiedenen Ordnern: die erste noch nicht vergebene.
    mIndex := 0;
    while (mName <> '') and (mIndex <= High(AFiles)) do
    begin
      if not mUsed[mIndex] and Matches(AFiles[mIndex], mName) then
      begin
        mUsed[mIndex] := True;
        Result := Result + [AFiles[mIndex]];
        mName := '';
      end;
      Inc(mIndex);
    end;
  end;
  for mIndex := 0 to High(AFiles) do
  begin
    if not mUsed[mIndex] then
    begin
      Result := Result + [AFiles[mIndex]];
    end;
  end;
end;

end.
