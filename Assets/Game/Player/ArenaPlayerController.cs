using UnityEngine;
using UnityEngine.InputSystem;
using TMPro;
using System;
using UnityEngine.Rendering;

// Handles side-view player movement, jumping, grounding, and blast-distance queries.
[RequireComponent(typeof(CharacterController))]
[AddComponentMenu("Arena/Player Controller")]
public sealed class ArenaPlayerController : MonoBehaviour
{
    private const float PlayerLabelHeight = 2.15f;
    private const float PlayerLabelCameraOffset = 3.5f;

    [Header("Player")]
    [SerializeField, Range(1, 4), Tooltip("Player 1 uses A/D and W or Space. Player 2 uses the arrow keys. Joined gamepads control their assigned player.")]
    private int playerNumber = 1;

    [Header("Movement")]
    [SerializeField, Min(0f), InspectorName("Move speed (units/s)")]
    private float moveSpeed = 7f;
    [SerializeField, Min(0.01f), InspectorName("Slow speed multiplier")]
    private float slowSpeedMultiplier = 0.5f;
    [SerializeField, Min(0.01f), InspectorName("Boost speed multiplier")]
    private float boostSpeedMultiplier = 1.5f;
    [SerializeField, Min(0.1f), InspectorName("Collectible effect duration (seconds)")]
    private float collectibleEffectDuration = 10f;

    [Header("Jump")]
    [SerializeField, Min(0f), InspectorName("Jump height (units)")]
    private float jumpHeight = 2.5f;

    [Tooltip("Player acceleration along Y. Negative values pull downward; separate from bomb acceleration.")]
    [SerializeField, InspectorName("Gravity (units/s²)")]
    private float gravity = -25f;

    [Header("Jump assistance")]
    [Tooltip("How long a jump remains allowed after walking off an edge.")]
    [SerializeField, Range(0f, 0.2f), InspectorName("Coyote time (seconds)")]
    private float coyoteTime = 0.1f;

    [Tooltip("How long a jump pressed before landing is remembered.")]
    [SerializeField, Range(0f, 0.2f), InspectorName("Jump buffer (seconds)")]
    private float jumpBufferTime = 0.1f;

    private CharacterController controller;
    private float verticalSpeed;
    private float coyoteRemaining;
    private float jumpBufferRemaining;
    private bool wasGrounded;
    private Animator animator;
    private ArenaSession session;
    private MaterialPropertyBlock characterColorProperties;
    private TextMeshPro playerLabel;
    private Collider lastPlainCollider;
    private PlayerBodyDamage bodyDamage;
    private static readonly int RunningParameter = Animator.StringToHash("Running");

    // Used to remember the player's original scale.
    private Vector3 originalScale;
    private float fixedZPosition;
    private float speedMultiplier = 1f;
    private float speedEffectRemaining;
    private float invincibilityRemaining;

    // Which speed item is currently changing this player's speed.
    public enum SpeedEffect { None, Boost, Slow }

    public int PlayerNumber => playerNumber;
    public int Coins { get; private set; }
    public bool IsInvincible => invincibilityRemaining > 0f;
    public float InvincibilityRemaining => invincibilityRemaining;
    public float SpeedEffectRemaining => speedEffectRemaining;
    public SpeedEffect ActiveSpeedEffect { get; private set; }
    public Color CharacterColor { get; private set; } = Color.white;
    public event Action<int> CoinsChanged;

    private void Awake()
    {
        session = FindFirstObjectByType<ArenaSession>();
        controller = GetComponent<CharacterController>();
        animator = GetComponentInChildren<Animator>();
        characterColorProperties = new MaterialPropertyBlock();

        // Save the player's starting scale.
        originalScale = transform.localScale;
        fixedZPosition = transform.position.z;
        ApplyCharacterColor();
        // Shows a glow while an item effect is active.
        if (!TryGetComponent(out PlayerItemGlow _)) gameObject.AddComponent<PlayerItemGlow>();
        // Knocks limbs off on blast grazes and bursts the body on death.
        if (!TryGetComponent(out bodyDamage)) bodyDamage = gameObject.AddComponent<PlayerBodyDamage>();
    }

    // A hit from the edge of a blast. Returns true if it should kill.
    public bool TakeGraze(Vector2 blastCenter) => bodyDamage == null || bodyDamage.TakeGraze(blastCenter);

    // Throws the body out as chunks; the caller then removes the player.
    public void Burst(Vector2 blastCenter)
    {
        if (bodyDamage != null) bodyDamage.Burst(blastCenter);
    }

    public void RestoreBody()
    {
        if (bodyDamage != null) bodyDamage.RestoreBody();
    }

    private void Start()
    {
        CreatePlayerLabel();
    }

    private void Update()
    {
        UpdateCollectibleEffects();

        if (session != null && session.IsPaused)
            return;
        if (session != null && !session.IsPlaying)
        {
            if (animator != null) animator.SetBool(RunningParameter, false);
            return;
        }
        float input = ReadMovement();

        if (animator != null)
            animator.SetBool(RunningParameter, Mathf.Abs(input) > 0.01f);

        // Flip the player depending on movement direction.
        UpdateFacing(input);
        
        bool grounded = controller.isGrounded;

        if (grounded && !wasGrounded)
            coyoteRemaining = coyoteTime;
        else if (grounded && verticalSpeed <= 0f)
            coyoteRemaining = coyoteTime;
        else
            coyoteRemaining -= Time.deltaTime;

        if (JumpPressed())
            jumpBufferRemaining = jumpBufferTime + Time.deltaTime;
        else
            jumpBufferRemaining -= Time.deltaTime;

        if (grounded && verticalSpeed < 0f)
            verticalSpeed = -2f;

        if (jumpBufferRemaining > 0f && coyoteRemaining >= 0f)
        {
            verticalSpeed = Mathf.Sqrt(-2f * gravity * jumpHeight);
            jumpBufferRemaining = 0f;
            coyoteRemaining = -1f;
        }

        verticalSpeed += gravity * Time.deltaTime;

        Vector3 velocity = new Vector3(
            input * moveSpeed * speedMultiplier,
            verticalSpeed,
            0f
        );

        controller.Move(velocity * Time.deltaTime);

        // Keep the player on the side-view plane even if a collision moves it in Z.
        Vector3 position = transform.position;
        if (!Mathf.Approximately(position.z, fixedZPosition))
        {
            position.z = fixedZPosition;
            transform.position = position;
        }

        if ((controller.collisionFlags & CollisionFlags.Above) != 0
            && verticalSpeed > 0f)
        {
            verticalSpeed = 0f;
        }

        wasGrounded = grounded;
    }

    private void LateUpdate()
    {
        if (playerLabel == null || Camera.main == null)
            return;

        Vector3 directionToCamera = -Camera.main.transform.forward;
        playerLabel.transform.position = transform.position
            + Vector3.up * PlayerLabelHeight
            + directionToCamera * PlayerLabelCameraOffset;
        playerLabel.transform.rotation = Quaternion.LookRotation(Camera.main.transform.forward, Camera.main.transform.up);
    }

    private void CreatePlayerLabel()
    {
        if (playerLabel != null)
            return;

        GameObject labelObject = new GameObject("Player Label", typeof(TextMeshPro));
        labelObject.transform.position = transform.position + Vector3.up * PlayerLabelHeight;
        playerLabel = labelObject.GetComponent<TextMeshPro>();
        playerLabel.text = "P" + playerNumber;
        playerLabel.fontSize = 6f;
        playerLabel.alignment = TextAlignmentOptions.Center;
        playerLabel.horizontalAlignment = HorizontalAlignmentOptions.Center;
        playerLabel.verticalAlignment = VerticalAlignmentOptions.Middle;
        playerLabel.color = Color.white;
        playerLabel.outlineWidth = 0.2f;
        playerLabel.outlineColor = Color.black;
        playerLabel.sortingOrder = 10;

        MeshRenderer labelRenderer = labelObject.GetComponent<MeshRenderer>();
        labelRenderer.shadowCastingMode = ShadowCastingMode.Off;
        labelRenderer.receiveShadows = false;
        labelRenderer.allowOcclusionWhenDynamic = false;
        Material labelMaterial = labelRenderer.material;
        if (labelMaterial.HasProperty("_ZTest"))
            labelMaterial.SetInt("_ZTest", (int)CompareFunction.Always);
        if (labelMaterial.HasProperty("_ZWrite"))
            labelMaterial.SetInt("_ZWrite", 0);
        labelMaterial.renderQueue = 5000;
    }

    private void OnDestroy()
    {
        if (playerLabel != null)
            Destroy(playerLabel.gameObject);
    }

    public void ApplyCollectible(CollectibleItemType itemType)
    {
        switch (itemType)
        {
            case CollectibleItemType.SilverCoin:
                AddCoins(10);
                break;
            case CollectibleItemType.GoldCoin:
                AddCoins(50);
                break;
            case CollectibleItemType.Invincibility:
                invincibilityRemaining = collectibleEffectDuration;
                break;
            case CollectibleItemType.Slow:
                speedMultiplier = Mathf.Max(0.01f, slowSpeedMultiplier);
                speedEffectRemaining = collectibleEffectDuration;
                ActiveSpeedEffect = SpeedEffect.Slow;
                break;
            case CollectibleItemType.SpeedBoost:
                speedMultiplier = Mathf.Max(0.01f, boostSpeedMultiplier);
                speedEffectRemaining = collectibleEffectDuration;
                ActiveSpeedEffect = SpeedEffect.Boost;
                break;
        }
    }

    public void ResetCollectibleEffects()
    {
        speedMultiplier = 1f;
        speedEffectRemaining = 0f;
        invincibilityRemaining = 0f;
        ActiveSpeedEffect = SpeedEffect.None;
    }

    public void ResetRoundStats()
    {
        Coins = 0;
        CoinsChanged?.Invoke(Coins);
    }

    private void AddCoins(int amount)
    {
        Coins += amount;
        CoinsChanged?.Invoke(Coins);
    }

    private void UpdateCollectibleEffects()
    {
        if (invincibilityRemaining > 0f)
            invincibilityRemaining = Mathf.Max(0f, invincibilityRemaining - Time.deltaTime);

        if (speedEffectRemaining <= 0f)
            return;

        speedEffectRemaining = Mathf.Max(0f, speedEffectRemaining - Time.deltaTime);
        if (speedEffectRemaining <= 0f)
        {
            speedMultiplier = 1f;
            ActiveSpeedEffect = SpeedEffect.None;
        }
    }

    private void UpdateFacing(float input)
    {
        Vector3 scale = originalScale;

        // Moving left
        if (input < 0f)
        {
            scale.x = -Mathf.Abs(originalScale.x);
        }

        // Moving right
        else if (input > 0f)
        {
            scale.x = Mathf.Abs(originalScale.x);
        }

        // If input is 0, don't change the direction.
        else
        {
            return;
        }

        transform.localScale = scale;
    }

    private float ReadMovement()
    {
        float input = 0f;
        Keyboard keyboard = Keyboard.current;

        if (keyboard != null && MatchMenuUI.IsKeyboardEnabledForPlayer(playerNumber))
        {
            if (playerNumber == 1)
            {
                if (keyboard.aKey.isPressed)
                    input -= 1f;

                if (keyboard.dKey.isPressed)
                    input += 1f;
            }
            else if (playerNumber == 2)
            {
                if (keyboard.leftArrowKey.isPressed)
                    input -= 1f;

                if (keyboard.rightArrowKey.isPressed)
                    input += 1f;
            }
        }

        Gamepad gamepad = GetPlayerGamepad();
        if (gamepad != null)
        {
            float stick = gamepad.leftStick.ReadValue().x;

            if (Mathf.Abs(stick) > Mathf.Abs(input))
                input = stick;
        }

        return Mathf.Clamp(input, -1f, 1f);
    }

    private bool JumpPressed()
    {
        Keyboard keyboard = Keyboard.current;
        bool keyboardJump = false;

        if (keyboard != null && MatchMenuUI.IsKeyboardEnabledForPlayer(playerNumber))
        {
            if (playerNumber == 1)
            {
                keyboardJump = keyboard.spaceKey.wasPressedThisFrame
                               || keyboard.wKey.wasPressedThisFrame;
            }
            else if (playerNumber == 2)
            {
                keyboardJump = keyboard.upArrowKey.wasPressedThisFrame;
            }
        }

        Gamepad gamepad = GetPlayerGamepad();
        bool gamepadJump = gamepad != null && gamepad.buttonSouth.wasPressedThisFrame;

        return keyboardJump || gamepadJump;
    }

    private Gamepad GetPlayerGamepad()
    {
        return MatchMenuUI.GetGamepadForPlayer(playerNumber);
    }

    public void SetPlayerNumber(int number)
    {
        playerNumber = Mathf.Clamp(number, 1, 4);
        if (playerLabel != null)
            playerLabel.text = "P" + playerNumber;
        slowSpeedMultiplier = Mathf.Clamp(slowSpeedMultiplier, 0.01f, 1f);
        boostSpeedMultiplier = Mathf.Max(1f, boostSpeedMultiplier);
        collectibleEffectDuration = Mathf.Max(0.1f, collectibleEffectDuration);
        ApplyCharacterColor();
    }

    private void ApplyCharacterColor()
    {
        if (characterColorProperties == null)
            characterColorProperties = new MaterialPropertyBlock();

        Color color = MatchMenuUI.GetCharacterColorForPlayer(playerNumber);
        CharacterColor = color;
        foreach (Renderer targetRenderer in GetComponentsInChildren<Renderer>(true))
        {
            targetRenderer.GetPropertyBlock(characterColorProperties);
            characterColorProperties.SetColor("_BaseColor", color);
            characterColorProperties.SetColor("_Color", color);
            targetRenderer.SetPropertyBlock(characterColorProperties);
        }
    }

    private void OnEnable()
    {
        fixedZPosition = transform.position.z;
    }

    private void OnDisable()
    {
        verticalSpeed = 0f;
        coyoteRemaining = -1f;
        jumpBufferRemaining = 0f;
        wasGrounded = false;
    }

    private void OnControllerColliderHit(ControllerColliderHit hit)
    {
        // This runs every frame for the ground under the player. Skip the
        // hierarchy searches below for a collider already known to be plain.
        Collider hitCollider = hit.collider;
        if (hitCollider == lastPlainCollider)
            return;

        if (hitCollider.GetComponentInParent<EliminationBound>() != null)
        {
            if (session != null) session.KillPlayer(this);
            else gameObject.SetActive(false);
            return;
        }

        FallingCollectibleItem collectible = hitCollider.GetComponentInParent<FallingCollectibleItem>();
        if (collectible != null)
        {
            collectible.TryCollect(this);
            return;
        }

        Rigidbody body = hitCollider.attachedRigidbody;
        if (body == null || hitCollider.GetComponentInParent<GroundRubble>() == null)
        {
            if (body == null) lastPlainCollider = hitCollider;
            return;
        }
        if (body.isKinematic) return;
        Vector3 push = new Vector3(hit.moveDirection.x, 0.15f, 0f);
        body.AddForce(push * Mathf.Max(1f, moveSpeed), ForceMode.VelocityChange);
    }

    private void OnValidate()
    {
        gravity = Mathf.Min(gravity, -0.1f);
        playerNumber = Mathf.Clamp(playerNumber, 1, 4);
        slowSpeedMultiplier = Mathf.Clamp(slowSpeedMultiplier, 0.01f, 1f);
        boostSpeedMultiplier = Mathf.Max(1f, boostSpeedMultiplier);
        collectibleEffectDuration = Mathf.Max(0.1f, collectibleEffectDuration);
    }

    // Measure distance to the capsule side in XY, accounting for the capsule end caps.
    public float DistanceToBody(Vector2 point)
    {
        CharacterController body =
            controller != null
            ? controller
            : GetComponent<CharacterController>();

        Vector3 center = transform.TransformPoint(body.center);

        float radius =
            body.radius *
            Mathf.Max(Mathf.Abs(transform.lossyScale.x), Mathf.Abs(transform.lossyScale.z));

        float halfSegment =
            Mathf.Max(
                0f,
                body.height * Mathf.Abs(transform.lossyScale.y) * 0.5f - radius
            );

        Vector2 closest = new Vector2(
            center.x,
            Mathf.Clamp(
                point.y,
                center.y - halfSegment,
                center.y + halfSegment
            )
        );

        return Mathf.Max(
            0f,
            Vector2.Distance(point, closest) - radius
        );
    }
}
