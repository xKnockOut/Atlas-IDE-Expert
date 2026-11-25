unit Atlas.Common.Documents.FileBatch;

// Mehrere Dateien auf einmal schreiben, alles oder nichts: Scheitert eine, werden die schon geschriebenen auf ihren
// alten Text zurückgesetzt. Gemeinsam für die Sammelkorrektur (#1352) und die schreibenden MCP-Werkzeuge (#61).

interface

uses
  System.SysUtils;

type
  /// <summary>Schreibt AText nach AFileName (Kodierung und Zeilenenden erhalten); Fehler als Exception.</summary>
  TFileBatchWrite = reference to procedure(const AFileName, AText: string);

  EFileBatchWrite = class(Exception);

  TFileBatch = record
    /// <summary>ANewTexts[i] nach ANames[i] schreiben, alle oder keine: Scheitert eine Datei, werden die schon
    /// geschriebenen auf AOldTexts zurückgesetzt und EFileBatchWrite ausgelöst. Liefert die Anzahl der Dateien.
    /// </summary>
    class function WriteAll(const ANames, AOldTexts, ANewTexts: TArray<string>; const AWrite: TFileBatchWrite):
      Integer; static;
  end;

implementation

uses
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TFileBatchText = (WriteFailed);

const
  cTexts: array[TFileBatchText] of TAtlasText = (
    (De: 'Schreiben fehlgeschlagen (%s); alle Dateien zurückgesetzt.'; En: 'Writing failed (%s); all files restored.'));

{$SCOPEDENUMS OFF}

{ TFileBatch }

class function TFileBatch.WriteAll(const ANames, AOldTexts, ANewTexts: TArray<string>;
  const AWrite: TFileBatchWrite): Integer;
var
  mIndex, mWritten: Integer;
begin
  mWritten := 0;
  try
    for mIndex := 0 to High(ANames) do
    begin
      AWrite(ANames[mIndex], ANewTexts[mIndex]);
      Inc(mWritten);
    end;
  except
    on E: Exception do
    begin
      // Alles oder nichts: schon geschriebene Dateien zurücksetzen.
      for mIndex := mWritten - 1 downto 0 do
        try
          AWrite(ANames[mIndex], AOldTexts[mIndex]);
        except
          // Zurücksetzen nach Kräften; gemeldet wird der erste Fehler, der die übrigen Dateien verhindert hat.
          // lsp-ignore: catch-all-without-raise -- Zurücksetzen nach Kräften; der erste Fehler wird ausgelöst
          on Exception do
            Continue;
        end;
      raise EFileBatchWrite.CreateFmt(cTexts[TFileBatchText.WriteFailed].Text, [E.Message]);
    end;
  end;
  Result := mWritten;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Documents.FileBatch', cTexts);

end.
