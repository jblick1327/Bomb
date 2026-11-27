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
    [Tooltip("Plays in the Bridge level instead of the game loop music.")]
    [SerializeField] private AudioClip bridgeMusic;
    [Tooltip("Buying a character in the shop.")]
    [SerializeField] private AudioClip purchase;
    [Tooltip("Ground and blocks breaking, with a bomb's boom.")]
    [SerializeField] private AudioClip breaking;

    [Header("Countdown")]
    [SerializeField] private AudioClip countdownThree;
    [SerializeField] private AudioClip countdownTwo;
    [SerializeField] private AudioClip countdownOne;
    [SerializeField] private AudioClip countdownGo;

    [Header("Claymate voices")]
    [Tooltip("Picking up an item.")]
    [SerializeField] private AudioClip[] pickupVoices;
    [Tooltip("Hit by the edge of a blast (losing a limb).")]
    [SerializeField] private AudioClip[] hurtVoices;
    [Tooltip("Knocked out.")]
    [SerializeField] private AudioClip knockedOutVoice;
    [Tooltip("Sometimes follows a pickup, hurt or knocked-out voice.")]
    [SerializeField] private AudioClip giggle;
    [SerializeField, Range(0f, 1f)] private float giggleChance = .3f;
    [Tooltip("Chance of a giggle when any button is pressed.")]
    [SerializeField, Range(0f, 1f)] private float buttonGiggleChance = .25f;
    [Tooltip("A bomb went off just outside a player's reach.")]
    [SerializeField] private AudioClip[] nearMissVoices;
    [Tooltip("The round is over.")]
    [SerializeField] private AudioClip roundEndVoice;

    // How much each kind of voice matters: a voice can cut off one that
    // matters less, but not one that matters more.
    private enum Voice { Giggle, NearMiss, Pickup, Hurt, KnockedOut, RoundEnd }
    private const float NearMissCooldown = 2.5f;
    private const float RoundEndDelay = .6f;

    private AudioSource musicSource;
    private AudioSource effectsSource;
    private AudioSource voiceSource;
    private Voice playingVoice;
    private Coroutine voiceFollowUp;
    private float nextNearMissTime;
    private AudioClip lastPickupVoice;
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
        voiceSource = CreateSource("Voices", false);
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
            PlayGameLoopMusic(scene.name == "BridgeLevel" && bridgeMusic != null ? bridgeMusic : gameLoopMusic);
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

    public static void PlayPurchase()
    {
        instance?.PlayEffect(instance.purchase, Vector3.zero);
    }

    // The crumble of ground and blocks, together with the explosion's boom.
    public static void PlayBreaking(Vector3 position)
    {
        instance?.PlayEffect(instance.breaking, position);
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
        instance?.PlayButtonPop();
    }

    // ---------- Countdown ----------

    // The 3, 2, 1 before a round; 0 is "Go!".
    public static void PlayCountdown(int number)
    {
        if (instance == null) return;
        AudioClip clip = number == 3 ? instance.countdownThree
            : number == 2 ? instance.countdownTwo
            : number == 1 ? instance.countdownOne
            : number == 0 ? instance.countdownGo : null;
        instance.PlayEffect(clip, Vector3.zero);
    }

    // ---------- Claymate voices ----------

    public static void PlayPickupVoice()
    {
        if (instance == null) return;
        AudioClip clip = instance.PickDifferent(instance.pickupVoices, instance.lastPickupVoice);
        instance.lastPickupVoice = clip;
        instance.PlayVoice(clip, Voice.Pickup, true);
    }

    public static void PlayHurtVoice() => instance?.PlayVoice(Pick(instance.hurtVoices), Voice.Hurt, true);

    public static void PlayKnockedOutVoice() => instance?.PlayVoice(instance.knockedOutVoice, Voice.KnockedOut, true);

    // "Woah!" or "Woohoo!", at most once every few seconds.
    public static void PlayNearMissVoice()
    {
        if (instance == null || Time.unscaledTime < instance.nextNearMissTime) return;
        instance.nextNearMissTime = Time.unscaledTime + NearMissCooldown;
        instance.PlayVoice(Pick(instance.nearMissVoices), Voice.NearMiss, false);
    }

    // "Yay!" a moment after the round ends, so a knocked-out cry isn't cut off.
    // "Yay!" straight away (LET'S GO on the setup screen).
    public static void PlayCheerVoice() => instance?.PlayVoice(instance.roundEndVoice, Voice.RoundEnd, false);

    public static void PlayRoundEndVoice()
    {
        if (instance == null || instance.roundEndVoice == null) return;
        instance.StopFollowUp();
        AudioSource voice = instance.voiceSource;
        float stillTalking = voice.isPlaying && voice.clip != null ? voice.clip.length - voice.time : 0f;
        instance.voiceFollowUp = instance.StartCoroutine(instance.PlayAfter(
            Mathf.Max(RoundEndDelay, stillTalking + .1f), instance.roundEndVoice, Voice.RoundEnd));
    }

    private void PlayVoice(AudioClip clip, Voice kind, bool mayGiggle)
    {
        if (clip == null) return;
        if (voiceSource.isPlaying && playingVoice > kind) return;
        StopFollowUp();
        voiceSource.Stop();
        voiceSource.clip = clip;
        voiceSource.Play();
        playingVoice = kind;
        if (mayGiggle && giggle != null && Random.value < giggleChance)
            voiceFollowUp = StartCoroutine(PlayAfter(clip.length + .12f, giggle, Voice.Giggle));
    }

    private IEnumerator PlayAfter(float seconds, AudioClip clip, Voice kind)
    {
        yield return new WaitForSecondsRealtime(seconds);
        voiceFollowUp = null;
        // Unless something more important has started meanwhile.
        if (voiceSource.isPlaying && playingVoice > kind) yield break;
        voiceSource.Stop();
        voiceSource.clip = clip;
        voiceSource.Play();
        playingVoice = kind;
    }

    private void StopFollowUp()
    {
        if (voiceFollowUp == null) return;
        StopCoroutine(voiceFollowUp);
        voiceFollowUp = null;
    }

    private static AudioClip Pick(AudioClip[] clips) =>
        clips == null || clips.Length == 0 ? null : clips[Random.Range(0, clips.Length)];

    // A random clip, but not the same one twice in a row.
    private AudioClip PickDifferent(AudioClip[] clips, AudioClip last)
    {
        if (clips == null || clips.Length == 0) return null;
        if (clips.Length == 1) return clips[0];
        AudioClip clip;
        do clip = clips[Random.Range(0, clips.Length)]; while (clip == last);
        return clip;
    }

    // Every button's pop, now and then with a giggle. A more important voice
    // (LET'S GO's "Yay!") keeps the giggle from playing.
    private void PlayButtonPop()
    {
        PlayEffect(buttonPop, Vector3.zero);
        if (giggle != null && Random.value < buttonGiggleChance)
            PlayVoice(giggle, Voice.Giggle, false);
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

    // The level's music: its own track if it has one, else the game loop.
    private void PlayGameLoopMusic(AudioClip clip)
    {
        if (menuMusicRoutine != null)
        {
            StopCoroutine(menuMusicRoutine);
            menuMusicRoutine = null;
        }

        PlayMusic(clip);
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
