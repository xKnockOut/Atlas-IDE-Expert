unit BDLsp.Common.Compiler.Contract;

// Verträge der Compiler-Anbindung (#40): Meldungen von dcc32/dcc64 und der
// Prozess, der den Compiler startet. Den Prozess stellt BDLsp.Windows bereit.

interface

uses
  System.SysUtils;

type
  {$SCOPEDENUMS ON}
  TCompilerSeverity = (Hint, Warning, Error, Fatal);
  {$SCOPEDENUMS OFF}

  /// <summary>Eine Zeile der Compilerausgabe mit Fundstelle.</summary>
  TCompilerMessage = record
    /// <summary>Absoluter Pfad; '' bei Meldungen ohne Datei.</summary>
    FileName: string;
    /// <summary>Zeile ab 0; -1 ohne Zeile.</summary>
    Line: Integer;
    /// <summary>Spalte ab 0; -1 ohne Spalte (dann gilt die ganze Zeile).</summary>
    Column: Integer;
    Severity: TCompilerSeverity;
    /// <summary>Meldungsnummer wie E2003; '' wenn keine erkannt wurde.</summary>
    Code: string;
    Text: string;
  end;

  /// <summary>Aufruf des Compilers.</summary>
  TCompilerRequest = record
    Executable: string;
    Arguments: TArray<string>;
    WorkingDir: string;
  end;

  TCompilerLineEvent = reference to procedure(const ALine: string);

  /// <summary>Startet einen Prozess und liefert seine Ausgabe zeilenweise.</summary>
  ICompilerProcess = interface
    ['{0E3D3F59-6A51-4E0B-9C2A-8B7F1D4E6A20}']
    /// <summary>Wartet auf das Ende und liefert den Exit-Code. AOnLine erhält stdout und stderr.</summary>
    function Run(const ARequest: TCompilerRequest; const AOnLine: TCompilerLineEvent): Integer;
  end;

  ECompilerError = class(Exception);

implementation

end.
