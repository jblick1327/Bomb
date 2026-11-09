using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.UI;

[AddComponentMenu("Game/Audio")]
public sealed class GameAudio : MonoBehaviour
{
    private const string ResourcePath = "GameAudio";
    private static GameAudio instance;

    [SerializeField] private AudioClip bombExplosion;
    [SerializeField] private AudioClip buttonPop;
    [SerializeField] private AudioClip coinPickup;
    [SerializeField] private AudioClip whistle;
    [SerializeField] private AudioClip intro;
    [SerializeField] private AudioClip menuMusic;
    [SerializeField] private AudioClip gameLoopMusic;

    private AudioSource musicSource;
    private AudioSource effectsSource;
    private readonly HashSet<Button> registeredButtons = new HashSet<Button>();
    private Coroutine menuMusicRoutine;
    private bool introPlayed;

    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
    private static void Initialize()
    {
        if (instance != null)
            return;

        GameObject prefab = Resources.Load<GameObject>(ResourcePath);
        if (prefab == null)
        {
            Debug.LogError($"Game audio prefab could not be loaded from Resources/{ResourcePath}.");
            return;
        }

        GameObject audioObject = Instantiate(prefab);
        audioObject.name = "Game Audio";
    }

    private void Awake()
    {
        if (instance != null && instance != this)
        {
            Destroy(gameObject);
            return;
        }

        instance = this;
        DontDestroyOnLoad(gameObject);
        musicSource = CreateSource("Music", true);
        effectsSource = CreateSource("Effects", false);
        SceneManager.sceneLoaded += OnSceneLoaded;
    }

    private void OnDestroy()
    {
        if (instance != this)
            return;

        SceneManager.sceneLoaded -= OnSceneLoaded;
        instance = null;
    }

    private AudioSource CreateSource(string sourceName, bool loop)
    {
        GameObject sourceObject = new GameObject(sourceName);
        sourceObject.transform.SetParent(transform, false);
        AudioSource source = sourceObject.AddComponent<AudioSource>();
        source.playOnAwake = false;
        source.loop = loop;
        source.spatialBlend = 0f;
        return source;
    }

    private void OnSceneLoaded(Scene scene, LoadSceneMode mode)
    {
        RegisterSceneButtons();

        if (scene.name == "MainMenuScene" || scene.name == "LevelSetupScene")
            PlayMenuMusic();
        else if (scene.name == "Arena" || scene.name == "YardLevel"
            || scene.name == "BridgeLevel" || scene.name == "TowerLevel")
            PlayGameLoopMusic();
    }

    private void RegisterSceneButtons()
    {
        foreach (Button button in FindObjectsByType<Button>(FindObjectsInactive.Include, FindObjectsSortMode.None))
            RegisterButton(button);
    }

    public static void RegisterButton(Button button)
    {
        if (instance == null || button == null || instance.registeredButtons.Contains(button))
            return;

        instance.registeredButtons.Add(button);
        button.onClick.AddListener(instance.PlayButtonPop);
    }

    public static void PlayBombExplosion(Vector3 position)
    {
        instance?.PlayEffect(instance.bombExplosion, position);
    }

    public static void PlayCoinPickup(Vector3 position)
    {
        instance?.PlayEffect(instance.coinPickup, position);
    }

    public static void PlayWhistle()
    {
        instance?.PlayEffect(instance.whistle, Vector3.zero);
    }

    public static void PlayButtonPopSound()
    {
        instance?.PlayEffect(instance.buttonPop, Vector3.zero);
    }

    private void PlayButtonPop()
    {
        PlayEffect(buttonPop, Vector3.zero);
    }

    private void PlayEffect(AudioClip clip, Vector3 position)
    {
        if (clip == null)
            return;

        effectsSource.transform.position = position;
        effectsSource.PlayOneShot(clip);
    }

    private void PlayMenuMusic()
    {
        if (menuMusicRoutine != null)
            StopCoroutine(menuMusicRoutine);

        if (!introPlayed && intro != null)
        {
            introPlayed = true;
            menuMusicRoutine = StartCoroutine(PlayIntroThenMenu());
            return;
        }

        PlayMusic(menuMusic);
    }

    private IEnumerator PlayIntroThenMenu()
    {
        PlayMusic(intro, false);
        yield return new WaitForSecondsRealtime(intro.length);
        PlayMusic(menuMusic);
        menuMusicRoutine = null;
    }

    private void PlayGameLoopMusic()
    {
        if (menuMusicRoutine != null)
        {
            StopCoroutine(menuMusicRoutine);
            menuMusicRoutine = null;
        }

        PlayMusic(gameLoopMusic);
    }

    private void PlayMusic(AudioClip clip, bool loop = true)
    {
        if (clip == null)
            return;

        if (musicSource.clip == clip && musicSource.isPlaying)
        {
            musicSource.loop = loop;
            return;
        }

        musicSource.Stop();
        musicSource.clip = clip;
        musicSource.loop = loop;
        musicSource.Play();
    }
}
