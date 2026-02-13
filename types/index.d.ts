declare namespace CordovaPlugins {
  interface SiriIntentData {
      mediaName?: string;
      artistName?: string;
      albumName?: string;
      mediaType?: number;
  }

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
      onSiriIntent(callback: (data: SiriIntentData) => void): void;
  }
}