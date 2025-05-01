declare namespace CordovaPlugins {
  interface MyMusicPlugin {
      play(success: () => void, error: (err: any) => void): void;
      pause(success: () => void, error: (err: any) => void): void;
      setMetadata(
          title: string,
          artist: string,
          album: string,
          success: () => void,
          error: (err: any) => void
      ): void;
  }
}